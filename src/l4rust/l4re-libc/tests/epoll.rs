use l4re_libc::*;
use libc::{self, c_void};

#[test]
fn epoll_basic_event() {
    unsafe {
        // create eventfd
        let efd = libc::eventfd(0, 0);
        assert!(efd >= 0);

        let epfd = epoll_create1(0);
        assert!(epfd >= 0);

        let mut ev = epoll_event {
            events: EPOLLIN,
            data: epoll_data_t { fd: efd },
        };
        assert_eq!(0, epoll_ctl(epfd, EPOLL_CTL_ADD, efd, &mut ev));

        // trigger event
        let val: u64 = 1;
        let ptr = &val as *const u64 as *const c_void;
        assert_eq!(8, libc::write(efd, ptr, 8));

        let mut events = [epoll_event { events: 0, data: epoll_data_t { u64: 0 } }];
        let n = epoll_wait(epfd, events.as_mut_ptr(), 1, 100);
        assert_eq!(1, n);
        assert!(events[0].events & EPOLLIN != 0);

        libc::close(efd);
        libc::close(epfd);
    }
}
