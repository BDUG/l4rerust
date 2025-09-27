#![allow(non_camel_case_types)]

use libc::{c_char, c_int, c_uint, c_void, sigset_t, clockid_t, itimerspec, size_t};

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

pub const IN_CLOEXEC: c_int = 0o2000000;
pub const IN_NONBLOCK: c_int = 0o4000;

pub const IN_ACCESS: u32 = 0x00000001;
pub const IN_MODIFY: u32 = 0x00000002;
pub const IN_ATTRIB: u32 = 0x00000004;
pub const IN_CLOSE_WRITE: u32 = 0x00000008;
pub const IN_CLOSE_NOWRITE: u32 = 0x00000010;
pub const IN_OPEN: u32 = 0x00000020;
pub const IN_MOVED_FROM: u32 = 0x00000040;
pub const IN_MOVED_TO: u32 = 0x00000080;
pub const IN_CREATE: u32 = 0x00000100;
pub const IN_DELETE: u32 = 0x00000200;
pub const IN_DELETE_SELF: u32 = 0x00000400;
pub const IN_MOVE_SELF: u32 = 0x00000800;
pub const IN_UNMOUNT: u32 = 0x00002000;
pub const IN_Q_OVERFLOW: u32 = 0x00004000;
pub const IN_IGNORED: u32 = 0x00008000;
pub const IN_ONLYDIR: u32 = 0x01000000;
pub const IN_DONT_FOLLOW: u32 = 0x02000000;
pub const IN_EXCL_UNLINK: u32 = 0x04000000;
pub const IN_MASK_ADD: u32 = 0x20000000;
pub const IN_ISDIR: u32 = 0x40000000;
pub const IN_ONESHOT: u32 = 0x80000000;
pub const IN_ALL_EVENTS: u32 = IN_ACCESS | IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE |
    IN_CLOSE_NOWRITE | IN_OPEN | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE |
    IN_DELETE_SELF | IN_MOVE_SELF;

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

#[repr(C)]
#[derive(Copy, Clone)]
pub struct inotify_event {
    pub wd: c_int,
    pub mask: u32,
    pub cookie: u32,
    pub len: u32,
    pub name: [c_char; 0],
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

      pub fn inotify_init1(flags: c_int) -> c_int;
      pub fn inotify_add_watch(fd: c_int, pathname: *const c_char, mask: u32) -> c_int;
      pub fn inotify_rm_watch(fd: c_int, wd: c_int) -> c_int;
  }
