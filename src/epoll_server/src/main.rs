//! Epoll server for L4Re.
//!
//! This server exposes a tiny subset of Linux' epoll interface over L4 IPC.
//! Clients communicate with the server via the `global_epoll` capability. The
//! protocol mirrors the operations of `epoll_create1`, `epoll_ctl` and
//! `epoll_wait` in a minimal fashion. The server keeps epoll instances in user
//! space and uses the host's epoll implementation to drive readiness.

use core::mem::size_of;
use l4_sys::{l4_ipc_error, l4_msgtag, l4_utcb, l4_utcb_br};
use l4re::sys::{l4re_env, l4re_env_get_cap};
use libc::{self, c_int};
use slab::Slab;
use std::io;
use std::os::unix::io::RawFd;

/// Maximum number of buffer register words available.
const BR_WORDS: usize = l4_sys::consts::UtcbConsts::L4_UTCB_GENERIC_BUFFERS_SIZE as usize;
/// Reserve the first word for the payload length when serialising replies.
const BR_DATA_BYTES: usize = (BR_WORDS.saturating_sub(1)) * size_of::<u64>();
/// Size of a single `libc::epoll_event` structure.
const EPOLL_EVENT_SIZE: usize = size_of::<libc::epoll_event>();
/// Maximum number of epoll events that fit into the UTCB buffer registers.
const MAX_SERIALISED_EVENTS: usize = if EPOLL_EVENT_SIZE == 0 {
    0
} else {
    BR_DATA_BYTES / EPOLL_EVENT_SIZE
};

/// Operation codes understood by the server.
mod opcode {
    pub const CREATE1: u64 = 0;
    pub const CTL: u64 = 1;
    pub const WAIT: u64 = 2;
    pub const CLOSE: u64 = 3;
}

/// Representation of an epoll instance maintained by the server.
struct EpollInstance {
    fd: RawFd,
}

impl Drop for EpollInstance {
    fn drop(&mut self) {
        unsafe {
            libc::close(self.fd);
        }
    }
}

fn main() {
    unsafe { run() }
}

/// Convert the last OS error into a negative errno encoded as `u64`.
fn encode_errno() -> u64 {
    let err = io::Error::last_os_error()
        .raw_os_error()
        .unwrap_or(libc::EIO);
    (-(err as i64)) as u64
}

/// Write an empty payload into the UTCB buffer registers.
unsafe fn br_clear() {
    let br = &mut (*l4_utcb_br()).br;
    br[0] = 0;
}

/// Read a single epoll event from the buffer registers.
unsafe fn br_read_event() -> Option<libc::epoll_event> {
    if EPOLL_EVENT_SIZE == 0 {
        return None;
    }
    let br = &(*l4_utcb_br()).br;
    let len = br[0] as usize;
    if len < EPOLL_EVENT_SIZE {
        return None;
    }
    let ptr = br.as_ptr().add(1) as *const u8;
    let mut event = libc::epoll_event { events: 0, u64: 0 };
    std::ptr::copy_nonoverlapping(ptr, &mut event as *mut _ as *mut u8, EPOLL_EVENT_SIZE);
    Some(event)
}

/// Serialise a slice of epoll events into the buffer registers.
unsafe fn br_write_events(events: &[libc::epoll_event]) {
    let count = events.len().min(MAX_SERIALISED_EVENTS);
    let br = &mut (*l4_utcb_br()).br;
    let bytes = count * EPOLL_EVENT_SIZE;
    br[0] = bytes as u64;
    if bytes == 0 {
        return;
    }
    let dst = br.as_mut_ptr().add(1) as *mut u8;
    std::ptr::copy_nonoverlapping(events.as_ptr() as *const u8, dst, bytes);
}

/// Handle an `epoll_ctl` request.
fn handle_ctl(
    instances: &mut Slab<EpollInstance>,
    mr: &mut [u64; l4_sys::consts::UtcbConsts::L4_UTCB_MR_COUNT as usize],
) {
    let handle = mr[1] as usize;
    let op = mr[2] as c_int;
    let target_fd = mr[3] as c_int;

    let Some(instance) = instances.get(handle) else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
        unsafe { br_clear() };
        return;
    };

    let res = unsafe {
        match op {
            libc::EPOLL_CTL_DEL => {
                libc::epoll_ctl(instance.fd, op, target_fd, std::ptr::null_mut())
            }
            _ => {
                let Some(mut event) = (unsafe { br_read_event() }) else {
                    return mr[0] = (-(libc::EINVAL as i64)) as u64;
                };
                libc::epoll_ctl(instance.fd, op, target_fd, &mut event)
            }
        }
    };

    mr[0] = if res < 0 { encode_errno() } else { 0 };
    unsafe { br_clear() };
}

/// Handle an `epoll_wait` request.
fn handle_wait(
    instances: &mut Slab<EpollInstance>,
    mr: &mut [u64; l4_sys::consts::UtcbConsts::L4_UTCB_MR_COUNT as usize],
) {
    let handle = mr[1] as usize;
    let maxevents = mr[2] as c_int;
    let timeout = mr[3] as c_int;

    let Some(instance) = instances.get(handle) else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
        unsafe { br_clear() };
        return;
    };

    if maxevents <= 0 {
        mr[0] = (-(libc::EINVAL as i64)) as u64;
        unsafe { br_clear() };
        return;
    }

    if MAX_SERIALISED_EVENTS == 0 {
        mr[0] = (-(libc::EOVERFLOW as i64)) as u64;
        unsafe { br_clear() };
        return;
    }

    let limit = maxevents.min(MAX_SERIALISED_EVENTS as c_int) as usize;
    let mut events: Vec<libc::epoll_event> = Vec::with_capacity(limit);
    let res =
        unsafe { libc::epoll_wait(instance.fd, events.as_mut_ptr(), limit as c_int, timeout) };

    if res < 0 {
        mr[0] = encode_errno();
        unsafe { br_clear() };
        return;
    }

    unsafe { events.set_len(res as usize) };
    unsafe { br_write_events(&events) };
    mr[0] = res as u64;
}

/// Handle closing of an epoll instance.
fn handle_close(
    instances: &mut Slab<EpollInstance>,
    mr: &mut [u64; l4_sys::consts::UtcbConsts::L4_UTCB_MR_COUNT as usize],
) {
    let handle = mr[1] as usize;
    if instances.contains(handle) {
        instances.remove(handle);
        mr[0] = 0;
    } else {
        mr[0] = (-(libc::EBADF as i64)) as u64;
    }
    unsafe { br_clear() };
}

/// Main server loop performing IPC dispatch.
unsafe fn run() {
    let gate = l4re_env_get_cap("global_epoll").expect("IPC gate 'global_epoll' not provided");

    let gatelabel = 0b1111_0000u64;
    if l4_ipc_error(
        l4::l4_rcv_ep_bind_thread(gate, (*l4re_env()).main_thread, gatelabel),
        l4_utcb(),
    ) != 0
    {
        panic!("failed to bind IPC gate");
    }

    println!("epoll server ready");

    let mut instances: Slab<EpollInstance> = Slab::new();
    let mut label = 0u64;
    let mut tag = l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 });
    loop {
        if l4_ipc_error(tag, l4_utcb()) != 0 {
            tag = l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 });
            continue;
        }

        let mr = &mut (*l4::l4_utcb_mr()).mr;
        match mr[0] {
            opcode::CREATE1 => {
                let flags = mr[1] as c_int;
                let fd = unsafe { libc::epoll_create1(flags) };
                if fd < 0 {
                    mr[0] = encode_errno();
                } else {
                    let slot = instances.insert(EpollInstance { fd });
                    mr[0] = slot as u64;
                }
                br_clear();
            }
            opcode::CTL => handle_ctl(&mut instances, mr),
            opcode::WAIT => handle_wait(&mut instances, mr),
            opcode::CLOSE => handle_close(&mut instances, mr),
            _ => {
                mr[0] = (-(libc::ENOSYS as i64)) as u64;
                br_clear();
            }
        }

        tag = l4::l4_ipc_reply_and_wait(
            l4_utcb(),
            l4_msgtag(0, 1, 0, 0),
            &mut label,
            l4::l4_timeout_t { raw: 0 },
        );
    }
}
