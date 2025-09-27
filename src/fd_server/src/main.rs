//! Service providing Linux descriptor helper APIs (eventfd, timerfd,
//! signalfd, and inotify) over L4 IPC.

use core::mem::size_of;
use l4::sys::{
    l4_ipc_error, l4_ipc_reply_and_wait, l4_ipc_wait, l4_msgtag, l4_timeout_t, l4_utcb,
    l4_utcb_br, l4_utcb_mr,
};
use l4re::sys::{l4re_env, l4re_env_get_cap};
use libc::{self, c_int, c_long, c_uint, c_void, clockid_t, itimerspec, sigset_t};
use slab::Slab;
use std::collections::HashMap;
use std::ffi::CString;
use std::io;
use std::os::unix::io::RawFd;

/// Size of the UTCB buffer register payload in bytes (minus one length word).
const BR_WORDS: usize = l4_sys::consts::UtcbConsts::L4_UTCB_GENERIC_BUFFERS_SIZE as usize;
const BR_DATA_BYTES: usize = (BR_WORDS.saturating_sub(1)) * size_of::<u64>();

mod opcode {
    pub const EVENTFD_CREATE: u64 = 0;
    pub const EVENTFD_READ: u64 = 1;
    pub const EVENTFD_WRITE: u64 = 2;
    pub const EVENTFD_CLOSE: u64 = 3;

    pub const TIMERFD_CREATE: u64 = 16;
    pub const TIMERFD_SETTIME: u64 = 17;
    pub const TIMERFD_GETTIME: u64 = 18;
    pub const TIMERFD_READ: u64 = 19;
    pub const TIMERFD_CLOSE: u64 = 20;

    pub const SIGNALFD_CREATE: u64 = 32;
    pub const SIGNALFD_READ: u64 = 33;
    pub const SIGNALFD_CLOSE: u64 = 34;

    pub const INOTIFY_INIT: u64 = 48;
    pub const INOTIFY_ADD_WATCH: u64 = 49;
    pub const INOTIFY_RM_WATCH: u64 = 50;
    pub const INOTIFY_READ: u64 = 51;
    pub const INOTIFY_CLOSE: u64 = 52;
}

struct Eventfd {
    fd: RawFd,
}

impl Drop for Eventfd {
    fn drop(&mut self) {
        unsafe {
            libc::close(self.fd);
        }
    }
}

struct Timerfd {
    fd: RawFd,
}

impl Drop for Timerfd {
    fn drop(&mut self) {
        unsafe {
            libc::close(self.fd);
        }
    }
}

struct Signalfd {
    fd: RawFd,
}

impl Drop for Signalfd {
    fn drop(&mut self) {
        unsafe { libc::close(self.fd) };
    }
}

struct Inotify {
    fd: RawFd,
    watches: HashMap<i32, i32>,
}

impl Drop for Inotify {
    fn drop(&mut self) {
        unsafe {
            libc::close(self.fd);
        }
        self.watches.clear();
    }
}

fn main() {
    unsafe { run() }
}

fn encode_errno() -> u64 {
    let err = io::Error::last_os_error()
        .raw_os_error()
        .unwrap_or(libc::EIO);
    (-(err as i64)) as u64
}

unsafe fn br_clear() {
    (*l4_utcb_br()).br[0] = 0;
}

unsafe fn br_write_bytes(data: &[u8]) {
    let len = data.len().min(BR_DATA_BYTES);
    let br = &mut (*l4_utcb_br()).br;
    br[0] = len as u64;
    if len == 0 {
        return;
    }
    let dst = br.as_mut_ptr().add(1) as *mut u8;
    std::ptr::copy_nonoverlapping(data.as_ptr(), dst, len);
}

unsafe fn br_read_bytes(buf: &mut Vec<u8>) {
    let br = &(*l4_utcb_br()).br;
    let len = (br[0] as usize).min(BR_DATA_BYTES);
    buf.clear();
    buf.reserve(len);
    let src = br.as_ptr().add(1) as *const u8;
    buf.extend_from_slice(std::slice::from_raw_parts(src, len));
}

unsafe fn br_read_exact<const N: usize>() -> Option<[u8; N]> {
    if N == 0 {
        return Some([0; N]);
    }
    let br = &(*l4_utcb_br()).br;
    let len = br[0] as usize;
    if len < N {
        return None;
    }
    let mut out = [0u8; N];
    let src = br.as_ptr().add(1) as *const u8;
    std::ptr::copy_nonoverlapping(src, out.as_mut_ptr(), N);
    Some(out)
}

unsafe fn read_itimerspec() -> Option<itimerspec> {
    let bytes = br_read_exact::<{ size_of::<itimerspec>() }>()?;
    let mut spec = itimerspec {
        it_interval: libc::timespec { tv_sec: 0, tv_nsec: 0 },
        it_value: libc::timespec { tv_sec: 0, tv_nsec: 0 },
    };
    std::ptr::copy_nonoverlapping(
        bytes.as_ptr(),
        &mut spec as *mut _ as *mut u8,
        size_of::<itimerspec>(),
    );
    Some(spec)
}

unsafe fn write_itimerspec(spec: &itimerspec) {
    let mut bytes = [0u8; size_of::<itimerspec>()];
    std::ptr::copy_nonoverlapping(
        spec as *const _ as *const u8,
        bytes.as_mut_ptr(),
        size_of::<itimerspec>(),
    );
    br_write_bytes(&bytes);
}

unsafe fn read_sigset(expected: usize) -> Option<Vec<u8>> {
    let mut buf = Vec::new();
    br_read_bytes(&mut buf);
    if buf.len() != expected {
        return None;
    }
    Some(buf)
}

unsafe fn read_string() -> Option<CString> {
    let mut buf = Vec::new();
    br_read_bytes(&mut buf);
    if buf.last().copied() != Some(0) {
        buf.push(0);
    }
    CString::new(buf).ok()
}

unsafe fn handle_eventfd_create(eventfds: &mut Slab<Eventfd>, mr: &mut [u64]) {
    let initval = mr[1] as c_uint;
    let flags = mr[2] as c_int;
    let fd = libc::eventfd(initval, flags);
    if fd < 0 {
        mr[0] = encode_errno();
        return;
    }
    let slot = eventfds.insert(Eventfd { fd });
    mr[0] = slot as u64;
    br_clear();
}

unsafe fn handle_eventfd_read(eventfds: &mut Slab<Eventfd>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    let Some(entry) = eventfds.get(handle) else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
        br_clear();
        return;
    };
    let mut value: u64 = 0;
    let res = libc::read(
        entry.fd,
        &mut value as *mut u64 as *mut c_void,
        size_of::<u64>(),
    );
    if res != size_of::<u64>() as isize {
        mr[0] = encode_errno();
        br_clear();
        return;
    }
    mr[0] = 0;
    mr[1] = value;
    br_clear();
}

unsafe fn handle_eventfd_write(eventfds: &mut Slab<Eventfd>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    let value = mr[2];
    let Some(entry) = eventfds.get(handle) else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
        br_clear();
        return;
    };
    let res = libc::write(
        entry.fd,
        &value as *const u64 as *const c_void,
        size_of::<u64>(),
    );
    if res != size_of::<u64>() as isize {
        mr[0] = encode_errno();
    } else {
        mr[0] = 0;
    }
    br_clear();
}

unsafe fn handle_eventfd_close(eventfds: &mut Slab<Eventfd>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    if eventfds.contains(handle) {
        eventfds.remove(handle);
        mr[0] = 0;
    } else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
    }
    br_clear();
}

unsafe fn handle_timerfd_create(timerfds: &mut Slab<Timerfd>, mr: &mut [u64]) {
    let clockid = mr[1] as clockid_t;
    let flags = mr[2] as c_int;
    let fd = libc::timerfd_create(clockid, flags);
    if fd < 0 {
        mr[0] = encode_errno();
        br_clear();
        return;
    }
    let slot = timerfds.insert(Timerfd { fd });
    mr[0] = slot as u64;
    br_clear();
}

unsafe fn handle_timerfd_settime(timerfds: &mut Slab<Timerfd>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    let flags = mr[2] as c_int;
    let want_old = mr[3] != 0;
    let Some(entry) = timerfds.get(handle) else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
        br_clear();
        return;
    };
    let Some(new_value) = read_itimerspec() else {
        mr[0] = (-(libc::EINVAL as i64)) as u64;
        br_clear();
        return;
    };
    let mut old_value = itimerspec {
        it_interval: libc::timespec { tv_sec: 0, tv_nsec: 0 },
        it_value: libc::timespec { tv_sec: 0, tv_nsec: 0 },
    };
    let old_ptr = if want_old {
        &mut old_value as *mut itimerspec
    } else {
        core::ptr::null_mut()
    };
    let res = libc::timerfd_settime(entry.fd, flags, &new_value, old_ptr);
    if res < 0 {
        mr[0] = encode_errno();
        br_clear();
        return;
    }
    mr[0] = 0;
    if want_old {
        write_itimerspec(&old_value);
    } else {
        br_clear();
    }
}

unsafe fn handle_timerfd_gettime(timerfds: &mut Slab<Timerfd>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    let Some(entry) = timerfds.get(handle) else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
        br_clear();
        return;
    };
    let mut cur = itimerspec {
        it_interval: libc::timespec { tv_sec: 0, tv_nsec: 0 },
        it_value: libc::timespec { tv_sec: 0, tv_nsec: 0 },
    };
    let res = libc::timerfd_gettime(entry.fd, &mut cur);
    if res < 0 {
        mr[0] = encode_errno();
        br_clear();
        return;
    }
    mr[0] = 0;
    write_itimerspec(&cur);
}

unsafe fn handle_timerfd_read(timerfds: &mut Slab<Timerfd>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    let Some(entry) = timerfds.get(handle) else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
        br_clear();
        return;
    };
    let mut expirations: u64 = 0;
    let res = libc::read(
        entry.fd,
        &mut expirations as *mut u64 as *mut c_void,
        size_of::<u64>(),
    );
    if res != size_of::<u64>() as isize {
        mr[0] = encode_errno();
        br_clear();
        return;
    }
    mr[0] = 0;
    mr[1] = expirations;
    br_clear();
}

unsafe fn handle_timerfd_close(timerfds: &mut Slab<Timerfd>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    if timerfds.contains(handle) {
        timerfds.remove(handle);
        mr[0] = 0;
    } else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
    }
    br_clear();
}

unsafe fn handle_signalfd_create(signalfds: &mut Slab<Signalfd>, mr: &mut [u64]) {
    let target = mr[1] as isize;
    let flags = mr[2] as c_int;
    let size = mr[3] as usize;
    let Some(mask_bytes) = read_sigset(size) else {
        mr[0] = (-(libc::EINVAL as i64)) as u64;
        br_clear();
        return;
    };
    let raw_fd = if target >= 0 {
        let Some(existing) = signalfds.get(target as usize) else {
            mr[0] = (-(libc::EBADF as i64)) as u64;
            br_clear();
            return;
        };
        existing.fd
    } else {
        -1
    };
    let res_fd = libc::syscall(
        libc::SYS_signalfd4,
        raw_fd,
        mask_bytes.as_ptr() as *const sigset_t,
        size,
        flags,
    ) as c_int;
    if res_fd < 0 {
        mr[0] = encode_errno();
        br_clear();
        return;
    }
    if target >= 0 {
        mr[0] = 0;
        br_clear();
        return;
    }
    let slot = signalfds.insert(Signalfd { fd: res_fd });
    mr[0] = slot as u64;
    br_clear();
}

unsafe fn handle_signalfd_read(signalfds: &mut Slab<Signalfd>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    let max_bytes = (mr[2] as usize).min(BR_DATA_BYTES);
    let Some(entry) = signalfds.get(handle) else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
        br_clear();
        return;
    };
    if max_bytes == 0 {
        mr[0] = (-(libc::EINVAL as i64)) as u64;
        br_clear();
        return;
    }
    let mut buf = vec![0u8; max_bytes];
    let res = libc::read(entry.fd, buf.as_mut_ptr() as *mut c_void, max_bytes);
    if res < 0 {
        mr[0] = encode_errno();
        br_clear();
        return;
    }
    buf.truncate(res as usize);
    br_write_bytes(&buf);
    mr[0] = res as u64;
}

unsafe fn handle_signalfd_close(signalfds: &mut Slab<Signalfd>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    if signalfds.contains(handle) {
        signalfds.remove(handle);
        mr[0] = 0;
    } else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
    }
    br_clear();
}

unsafe fn handle_inotify_init(inotifies: &mut Slab<Inotify>, mr: &mut [u64]) {
    let flags = mr[1] as c_int;
    let fd = libc::inotify_init1(flags);
    if fd < 0 {
        mr[0] = encode_errno();
        br_clear();
        return;
    }
    let slot = inotifies.insert(Inotify {
        fd,
        watches: HashMap::new(),
    });
    mr[0] = slot as u64;
    br_clear();
}

unsafe fn handle_inotify_add_watch(inotifies: &mut Slab<Inotify>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    let mask = mr[2] as u32;
    let Some(entry) = inotifies.get_mut(handle) else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
        br_clear();
        return;
    };
    let Some(path) = read_string() else {
        mr[0] = (-(libc::EINVAL as i64)) as u64;
        br_clear();
        return;
    };
    let wd = libc::inotify_add_watch(entry.fd, path.as_ptr(), mask);
    if wd < 0 {
        mr[0] = encode_errno();
        br_clear();
        return;
    }
    entry.watches.insert(wd, wd);
    mr[0] = wd as u64;
    br_clear();
}

unsafe fn handle_inotify_rm_watch(inotifies: &mut Slab<Inotify>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    let wd = mr[2] as i32;
    let Some(entry) = inotifies.get_mut(handle) else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
        br_clear();
        return;
    };
    let res = libc::inotify_rm_watch(entry.fd, wd);
    if res < 0 {
        mr[0] = encode_errno();
    } else {
        mr[0] = 0;
        entry.watches.remove(&wd);
    }
    br_clear();
}

unsafe fn handle_inotify_read(inotifies: &mut Slab<Inotify>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    let max_bytes = (mr[2] as usize).min(BR_DATA_BYTES);
    let Some(entry) = inotifies.get(handle) else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
        br_clear();
        return;
    };
    if max_bytes == 0 {
        mr[0] = (-(libc::EINVAL as i64)) as u64;
        br_clear();
        return;
    }
    let mut buf = vec![0u8; max_bytes];
    let res = libc::read(entry.fd, buf.as_mut_ptr() as *mut c_void, max_bytes);
    if res < 0 {
        mr[0] = encode_errno();
        br_clear();
        return;
    }
    buf.truncate(res as usize);
    br_write_bytes(&buf);
    mr[0] = res as u64;
}

unsafe fn handle_inotify_close(inotifies: &mut Slab<Inotify>, mr: &mut [u64]) {
    let handle = mr[1] as usize;
    if inotifies.contains(handle) {
        inotifies.remove(handle);
        mr[0] = 0;
    } else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
    }
    br_clear();
}

unsafe fn run() {
    let gate = l4re_env_get_cap("global_fd").expect("IPC gate 'global_fd' not provided");

    let label = 0b1111_0101u64;
    if l4_ipc_error(
        l4::l4_rcv_ep_bind_thread(gate, (*l4re_env()).main_thread, label),
        l4_utcb(),
    ) != 0
    {
        panic!("failed to bind IPC gate");
    }

    println!("fd helper server ready");

    let mut eventfds = Slab::new();
    let mut timerfds = Slab::new();
    let mut signalfds = Slab::new();
    let mut inotifies = Slab::new();

    let mut badge = 0u64;
    let mut tag = l4_ipc_wait(l4_utcb(), &mut badge, l4_timeout_t { raw: 0 });

    loop {
        if l4_ipc_error(tag, l4_utcb()) != 0 {
            tag = l4_ipc_wait(l4_utcb(), &mut badge, l4_timeout_t { raw: 0 });
            continue;
        }

        let mr = &mut (*l4_utcb_mr()).mr;
        match mr[0] {
            opcode::EVENTFD_CREATE => handle_eventfd_create(&mut eventfds, mr),
            opcode::EVENTFD_READ => handle_eventfd_read(&mut eventfds, mr),
            opcode::EVENTFD_WRITE => handle_eventfd_write(&mut eventfds, mr),
            opcode::EVENTFD_CLOSE => handle_eventfd_close(&mut eventfds, mr),

            opcode::TIMERFD_CREATE => handle_timerfd_create(&mut timerfds, mr),
            opcode::TIMERFD_SETTIME => handle_timerfd_settime(&mut timerfds, mr),
            opcode::TIMERFD_GETTIME => handle_timerfd_gettime(&mut timerfds, mr),
            opcode::TIMERFD_READ => handle_timerfd_read(&mut timerfds, mr),
            opcode::TIMERFD_CLOSE => handle_timerfd_close(&mut timerfds, mr),

            opcode::SIGNALFD_CREATE => handle_signalfd_create(&mut signalfds, mr),
            opcode::SIGNALFD_READ => handle_signalfd_read(&mut signalfds, mr),
            opcode::SIGNALFD_CLOSE => handle_signalfd_close(&mut signalfds, mr),

            opcode::INOTIFY_INIT => handle_inotify_init(&mut inotifies, mr),
            opcode::INOTIFY_ADD_WATCH => handle_inotify_add_watch(&mut inotifies, mr),
            opcode::INOTIFY_RM_WATCH => handle_inotify_rm_watch(&mut inotifies, mr),
            opcode::INOTIFY_READ => handle_inotify_read(&mut inotifies, mr),
            opcode::INOTIFY_CLOSE => handle_inotify_close(&mut inotifies, mr),

            _ => {
                mr[0] = (-(libc::ENOSYS as c_long)) as u64;
                br_clear();
            }
        }

        tag = l4_ipc_reply_and_wait(
            l4_utcb(),
            l4_msgtag(0, 1, 0, 0),
            &mut badge,
            l4_timeout_t { raw: 0 },
        );
    }
}
