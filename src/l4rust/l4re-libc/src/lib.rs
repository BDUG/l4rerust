#![allow(non_camel_case_types)]

use libc::{c_int, c_uint, c_void, sigset_t, clockid_t, itimerspec, size_t};

#[repr(C)]
#[derive(Copy, Clone)]
pub union epoll_data_t {
    pub ptr: *mut c_void,
    pub fd: c_int,
    pub u32: u32,
    pub u64: u64,
}

#[repr(C)]
#[derive(Copy, Clone)]
pub struct epoll_event {
    pub events: u32,
    pub data: epoll_data_t,
}

pub type eventfd_t = u64;

pub const EFD_SEMAPHORE: c_int = 1;
pub const EFD_CLOEXEC: c_int = 0o2000000;
pub const EFD_NONBLOCK: c_int = 0o4000;

pub const TFD_CLOEXEC: c_int = 0o2000000;
pub const TFD_NONBLOCK: c_int = 0o4000;
pub const TFD_TIMER_ABSTIME: c_int = 1;
pub const TFD_TIMER_CANCEL_ON_SET: c_int = 2;

pub const SFD_CLOEXEC: c_int = 0o2000000;
pub const SFD_NONBLOCK: c_int = 0o4000;

pub const EPOLLIN: u32 = 0x001;
pub const EPOLLPRI: u32 = 0x002;
pub const EPOLLOUT: u32 = 0x004;
pub const EPOLLRDNORM: u32 = 0x040;
pub const EPOLLRDBAND: u32 = 0x080;
pub const EPOLLWRNORM: u32 = 0x100;
pub const EPOLLWRBAND: u32 = 0x200;
pub const EPOLLMSG: u32 = 0x400;
pub const EPOLLERR: u32 = 0x008;
pub const EPOLLHUP: u32 = 0x010;
pub const EPOLLRDHUP: u32 = 0x2000;
pub const EPOLLEXCLUSIVE: u32 = 1u32 << 28;
pub const EPOLLWAKEUP: u32 = 1u32 << 29;
pub const EPOLLONESHOT: u32 = 1u32 << 30;
pub const EPOLLET: u32 = 1u32 << 31;

pub const EPOLL_CTL_ADD: c_int = 1;
pub const EPOLL_CTL_DEL: c_int = 2;
pub const EPOLL_CTL_MOD: c_int = 3;

#[repr(C)]
#[derive(Copy, Clone)]
pub struct signalfd_siginfo {
    pub ssi_signo: u32,
    pub ssi_errno: i32,
    pub ssi_code: i32,
    pub ssi_pid: u32,
    pub ssi_uid: u32,
    pub ssi_fd: i32,
    pub ssi_tid: u32,
    pub ssi_band: u32,
    pub ssi_overrun: u32,
    pub ssi_trapno: u32,
    pub ssi_status: i32,
    pub ssi_int: i32,
    pub ssi_ptr: u64,
    pub ssi_utime: u64,
    pub ssi_stime: u64,
    pub ssi_addr: u64,
    pub ssi_addr_lsb: u16,
    pub __pad2: u16,
    pub ssi_syscall: i32,
    pub ssi_call_addr: u64,
    pub ssi_arch: u32,
    pub __pad: [u8; 28],
}

extern "C" {
    pub fn eventfd(initval: c_uint, flags: c_int) -> c_int;
    pub fn eventfd_read(fd: c_int, value: *mut eventfd_t) -> c_int;
    pub fn eventfd_write(fd: c_int, value: eventfd_t) -> c_int;

    pub fn epoll_create(size: c_int) -> c_int;
    pub fn epoll_create1(flags: c_int) -> c_int;
    pub fn epoll_ctl(epfd: c_int, op: c_int, fd: c_int, event: *mut epoll_event) -> c_int;
    pub fn epoll_wait(epfd: c_int, events: *mut epoll_event, maxevents: c_int, timeout: c_int) -> c_int;
    pub fn epoll_pwait(epfd: c_int, events: *mut epoll_event, maxevents: c_int, timeout: c_int,
        sigmask: *const sigset_t) -> c_int;

    pub fn timerfd_create(clockid: clockid_t, flags: c_int) -> c_int;
    pub fn timerfd_settime(fd: c_int, flags: c_int, new_value: *const itimerspec,
        old_value: *mut itimerspec) -> c_int;
      pub fn timerfd_gettime(fd: c_int, curr_value: *mut itimerspec) -> c_int;

      pub fn signalfd(fd: c_int, mask: *const sigset_t, flags: c_int) -> c_int;
      pub fn signalfd4(fd: c_int, mask: *const sigset_t, size: size_t, flags: c_int) -> c_int;
  }
