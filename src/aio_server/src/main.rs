//! POSIX AIO service proxying aio_* calls over L4 IPC.

use core::mem::size_of;
use l4::sys::{
    l4_ipc_error, l4_ipc_reply_and_wait, l4_ipc_wait, l4_msgtag, l4_timeout_t, l4_utcb, l4_utcb_br,
    l4_utcb_mr,
};
use l4re::sys::{l4re_env, l4re_env_get_cap};
use libc::{self, aiocb, c_int, c_void};
use slab::Slab;
use std::cmp::min;
use std::os::unix::io::RawFd;

const BR_WORDS: usize = l4_sys::consts::UtcbConsts::L4_UTCB_GENERIC_BUFFERS_SIZE as usize;
const BR_DATA_BYTES: usize = (BR_WORDS.saturating_sub(1)) * size_of::<u64>();

mod opcode {
    pub const AIO_READ: u64 = 0;
    pub const AIO_WRITE: u64 = 1;
    pub const AIO_ERROR: u64 = 2;
    pub const AIO_RETURN: u64 = 3;
    pub const AIO_CANCEL: u64 = 4;
    pub const AIO_SUSPEND: u64 = 5;
    pub const AIO_FSYNC: u64 = 6;
    pub const LIO_LISTIO: u64 = 7;
}

#[derive(Debug)]
enum OperationKind {
    Read,
    Write,
    Fsync,
}

struct Operation {
    kind: OperationKind,
    fd: RawFd,
    result: isize,
    error: c_int,
    buffer: Vec<u8>,
}

fn encode_errno_raw(err: c_int) -> u64 {
    (-(err as i64)) as u64
}

unsafe fn br_clear() {
    (*l4_utcb_br()).br[0] = 0;
}

unsafe fn br_bytes_mut() -> (*mut u8, usize) {
    let br = &mut (*l4_utcb_br()).br;
    let len = min(br[0] as usize, BR_DATA_BYTES);
    (br.as_mut_ptr().add(1) as *mut u8, len)
}

unsafe fn br_bytes() -> (*const u8, usize) {
    let br = &(*l4_utcb_br()).br;
    let len = min(br[0] as usize, BR_DATA_BYTES);
    (br.as_ptr().add(1) as *const u8, len)
}

unsafe fn read_aiocb(expected: usize) -> Result<aiocb, ()> {
    if expected == 0 || expected > BR_DATA_BYTES {
        return Err(());
    }
    let (ptr, len) = br_bytes();
    if len < expected {
        return Err(());
    }
    let mut cb: aiocb = core::mem::zeroed();
    let dst = &mut cb as *mut aiocb as *mut u8;
    core::ptr::copy_nonoverlapping(ptr, dst, core::cmp::min(expected, size_of::<aiocb>()));
    Ok(cb)
}

fn read_buffer_from_aiocb(cb: &aiocb) -> (usize, libc::off_t) {
    let len = cb.aio_nbytes as usize;
    let offset = cb.aio_offset as libc::off_t;
    (len, offset)
}

fn perform_read(fd: RawFd, len: usize, offset: libc::off_t) -> Result<(Vec<u8>, isize), c_int> {
    if len > BR_DATA_BYTES {
        return Err(libc::EOVERFLOW);
    }
    let mut buf = vec![0u8; len];
    let res = unsafe { libc::pread(fd, buf.as_mut_ptr() as *mut c_void, len, offset) };
    if res < 0 {
        let err = unsafe { *libc::__errno_location() };
        Err(err)
    } else {
        let res = res as isize;
        buf.truncate(res as usize);
        Ok((buf, res))
    }
}

fn perform_write(fd: RawFd, payload: &[u8], offset: libc::off_t) -> Result<isize, c_int> {
    let res = unsafe { libc::pwrite(fd, payload.as_ptr() as *const c_void, payload.len(), offset) };
    if res < 0 {
        let err = unsafe { *libc::__errno_location() };
        Err(err)
    } else {
        Ok(res as isize)
    }
}

fn perform_fsync(fd: RawFd, op: c_int) -> Result<isize, c_int> {
    let res = if op == libc::O_DSYNC {
        unsafe { libc::fdatasync(fd) }
    } else {
        unsafe { libc::fsync(fd) }
    };
    if res < 0 {
        let err = unsafe { *libc::__errno_location() };
        Err(err)
    } else {
        Ok(0)
    }
}

fn handle_aio_read(ops: &mut Slab<Operation>, mr: &mut [u64]) {
    let struct_len = mr[1] as usize;
    let cb = unsafe { read_aiocb(struct_len) };
    let cb = match cb {
        Ok(cb) => cb,
        Err(_) => {
            mr[0] = encode_errno_raw(libc::EINVAL);
            unsafe { br_clear() };
            return;
        }
    };

    let (len, offset) = read_buffer_from_aiocb(&cb);
    match perform_read(cb.aio_fildes, len, offset) {
        Ok((buffer, result)) => {
            let slot = ops.insert(Operation {
                kind: OperationKind::Read,
                fd: cb.aio_fildes,
                result,
                error: 0,
                buffer,
            });
            mr[0] = slot as u64;
        }
        Err(err) => {
            mr[0] = encode_errno_raw(err);
        }
    }
    unsafe { br_clear() };
}

fn handle_aio_write(ops: &mut Slab<Operation>, mr: &mut [u64]) {
    let struct_len = mr[1] as usize;
    let payload_len = mr[2] as usize;
    let (ptr, total) = unsafe { br_bytes() };
    if total < struct_len.saturating_add(payload_len) {
        mr[0] = encode_errno_raw(libc::EINVAL);
        unsafe { br_clear() };
        return;
    }

    let mut cb: aiocb = unsafe { core::mem::zeroed() };
    unsafe {
        core::ptr::copy_nonoverlapping(ptr, &mut cb as *mut _ as *mut u8, core::cmp::min(struct_len, size_of::<aiocb>()));
    }
    let payload_ptr = unsafe { ptr.add(struct_len) };
    let payload = unsafe { std::slice::from_raw_parts(payload_ptr, payload_len) };

    match perform_write(cb.aio_fildes, payload, cb.aio_offset as libc::off_t) {
        Ok(result) => {
            let slot = ops.insert(Operation {
                kind: OperationKind::Write,
                fd: cb.aio_fildes,
                result,
                error: 0,
                buffer: Vec::new(),
            });
            mr[0] = slot as u64;
        }
        Err(err) => {
            mr[0] = encode_errno_raw(err);
        }
    }
    unsafe { br_clear() };
}

fn handle_aio_fsync(ops: &mut Slab<Operation>, mr: &mut [u64]) {
    let struct_len = mr[1] as usize;
    let op_kind = mr[3] as c_int;
    let cb = unsafe { read_aiocb(struct_len) };
    let cb = match cb {
        Ok(cb) => cb,
        Err(_) => {
            mr[0] = encode_errno_raw(libc::EINVAL);
            unsafe { br_clear() };
            return;
        }
    };

    match perform_fsync(cb.aio_fildes, op_kind) {
        Ok(result) => {
            let slot = ops.insert(Operation {
                kind: OperationKind::Fsync,
                fd: cb.aio_fildes,
                result,
                error: 0,
                buffer: Vec::new(),
            });
            mr[0] = slot as u64;
        }
        Err(err) => {
            mr[0] = encode_errno_raw(err);
        }
    }
    unsafe { br_clear() };
}

fn handle_aio_error(ops: &Slab<Operation>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    if let Some(op) = ops.get(handle) {
        mr[0] = op.error as u64;
    } else {
        mr[0] = encode_errno_raw(libc::EINVAL);
    }
    unsafe { br_clear() };
}

fn handle_aio_return(ops: &mut Slab<Operation>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    if ops.contains(handle) {
        let op = ops.remove(handle);
        if op.error != 0 {
            mr[0] = encode_errno_raw(op.error);
            unsafe { br_clear() };
            return;
        }
        mr[0] = op.result as u64;
        match op.kind {
            OperationKind::Read => {
                mr[1] = op.buffer.len() as u64;
                unsafe {
                    let br = &mut (*l4_utcb_br()).br;
                    let len = op.buffer.len().min(BR_DATA_BYTES);
                    br[0] = len as u64;
                    if len > 0 {
                        let dst = br.as_mut_ptr().add(1) as *mut u8;
                        std::ptr::copy_nonoverlapping(op.buffer.as_ptr(), dst, len);
                    }
                }
            }
            _ => {
                mr[1] = 0;
                unsafe { br_clear() };
            }
        }
        return;
    }
    mr[0] = encode_errno_raw(libc::EINVAL);
    unsafe { br_clear() };
}

fn handle_aio_cancel(ops: &mut Slab<Operation>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    if ops.contains(handle) {
        ops.remove(handle);
        mr[0] = libc::AIO_ALLDONE as u64;
    } else {
        mr[0] = libc::AIO_ALLDONE as u64;
    }
    unsafe { br_clear() };
}

fn handle_aio_suspend(mr: &mut [u64]) {
    let _nent = mr[1] as usize;
    // All operations are completed synchronously for now.
    mr[0] = 0;
    unsafe { br_clear() };
}

fn handle_lio_listio(mr: &mut [u64]) {
    // This server currently executes list I/O on the client side.
    mr[0] = encode_errno_raw(libc::ENOSYS);
    unsafe { br_clear() };
}

fn main() {
    unsafe { run() }
}

unsafe fn run() {
    let gate = l4re_env_get_cap("global_aio").expect("IPC gate 'global_aio' not provided");

    let gatelabel = 0b1111_0000u64;
    if l4_ipc_error(
        l4::l4_rcv_ep_bind_thread(gate, (*l4re_env()).main_thread, gatelabel),
        l4_utcb(),
    ) != 0
    {
        panic!("failed to bind IPC gate");
    }

    println!("aio server ready");

    let mut ops: Slab<Operation> = Slab::new();
    let mut label = 0u64;
    let mut tag = l4_ipc_wait(l4_utcb(), &mut label, l4_timeout_t { raw: 0 });
    loop {
        if l4_ipc_error(tag, l4_utcb()) != 0 {
            tag = l4_ipc_wait(l4_utcb(), &mut label, l4_timeout_t { raw: 0 });
            continue;
        }

        let mr = &mut (*l4_utcb_mr()).mr;
        match mr[0] {
            opcode::AIO_READ => handle_aio_read(&mut ops, mr),
            opcode::AIO_WRITE => handle_aio_write(&mut ops, mr),
            opcode::AIO_ERROR => handle_aio_error(&ops, mr),
            opcode::AIO_RETURN => handle_aio_return(&mut ops, mr),
            opcode::AIO_CANCEL => handle_aio_cancel(&mut ops, mr),
            opcode::AIO_SUSPEND => handle_aio_suspend(mr),
            opcode::AIO_FSYNC => handle_aio_fsync(&mut ops, mr),
            opcode::LIO_LISTIO => handle_lio_listio(mr),
            _ => {
                mr[0] = encode_errno_raw(libc::ENOSYS);
                br_clear();
            }
        }

        tag = l4_ipc_reply_and_wait(
            l4_utcb(),
            l4_msgtag(0, 2, 0, 0),
            &mut label,
            l4_timeout_t { raw: 0 },
        );
    }
}
