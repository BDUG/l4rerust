use l4re_libc::*;
use std::{thread, time::Duration};
use libc;

#[test]
fn eventfd_cross_thread() {
    unsafe {
        let efd = eventfd(0, 0);
        assert!(efd >= 0);

        let reader = thread::spawn(move || {
            let mut val: eventfd_t = 0;
            assert_eq!(0, eventfd_read(efd, &mut val));
            val
        });

        thread::sleep(Duration::from_millis(50));
        assert_eq!(0, eventfd_write(efd, 1));

        let val = reader.join().unwrap();
        assert_eq!(val, 1);

        libc::close(efd);
    }
}
