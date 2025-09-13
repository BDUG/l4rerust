use l4re_libc::*;
use libc::{self, c_void, itimerspec, timespec};

#[test]
fn timerfd_epoll_ready() {
    unsafe {
        let tfd = timerfd_create(libc::CLOCK_MONOTONIC, 0);
        assert!(tfd >= 0);

        let new_value = itimerspec {
            it_interval: timespec { tv_sec: 0, tv_nsec: 0 },
            it_value: timespec { tv_sec: 0, tv_nsec: 100_000_000 },
        };
        assert_eq!(0, timerfd_settime(tfd, 0, &new_value, std::ptr::null_mut()));

        let epfd = epoll_create1(0);
        assert!(epfd >= 0);

        let mut ev = epoll_event {
            events: EPOLLIN,
            data: epoll_data_t { fd: tfd },
        };
        assert_eq!(0, epoll_ctl(epfd, EPOLL_CTL_ADD, tfd, &mut ev));

        let mut events = [epoll_event { events: 0, data: epoll_data_t { u64: 0 } }];
        let n = epoll_wait(epfd, events.as_mut_ptr(), 1, 500);
        assert_eq!(1, n);
        assert!(events[0].events & EPOLLIN != 0);

        let mut expirations: u64 = 0;
        let ptr = &mut expirations as *mut u64 as *mut c_void;
        assert_eq!(8, libc::read(tfd, ptr, 8));
        assert_eq!(1, expirations);

        libc::close(tfd);
        libc::close(epfd);
    }
}
