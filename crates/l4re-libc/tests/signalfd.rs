use l4re_libc::*;
use libc;
use std::{mem, ptr};

#[test]
fn signalfd_sigusr1() {
    unsafe {
        // block SIGUSR1 so it can be received via signalfd
        let mut mask: libc::sigset_t = mem::zeroed();
        libc::sigemptyset(&mut mask);
        libc::sigaddset(&mut mask, libc::SIGUSR1);
        assert_eq!(0, libc::sigprocmask(libc::SIG_BLOCK, &mask, ptr::null_mut()));

        // create signalfd to receive SIGUSR1
        let fd = signalfd(-1, &mask, 0);
        assert!(fd >= 0);

        // send SIGUSR1 to the current thread
        assert_eq!(0, libc::raise(libc::SIGUSR1));

        let mut info: signalfd_siginfo = mem::zeroed();
        let res = libc::read(
            fd,
            &mut info as *mut _ as *mut libc::c_void,
            mem::size_of::<signalfd_siginfo>() as libc::size_t,
        );
        assert_eq!(res as usize, mem::size_of::<signalfd_siginfo>());
        assert_eq!(info.ssi_signo, libc::SIGUSR1 as u32);

        libc::close(fd);
    }
}
