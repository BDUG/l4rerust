use l4re_libc::*;
use libc::{c_void};
use std::ffi::CString;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::os::unix::ffi::OsStrExt;

#[test]
fn inotify_modify_event() {
    unsafe {
        let dir = std::env::temp_dir();
        let path = dir.join("inotify_test_file");

        {
            let mut f = File::create(&path).unwrap();
            f.write_all(b"initial").unwrap();
        }

        let c_path = CString::new(path.as_os_str().as_bytes()).unwrap();
        let fd = inotify_init1(0);
        assert!(fd >= 0);
        let wd = inotify_add_watch(fd, c_path.as_ptr(), IN_MODIFY);
        assert!(wd >= 0);

        {
            let mut f = OpenOptions::new().write(true).open(&path).unwrap();
            f.write_all(b"update").unwrap();
            f.flush().unwrap();
        }

        let mut buf = [0u8; 1024];
        let n = libc::read(fd, buf.as_mut_ptr() as *mut c_void, buf.len());
        assert!(n as usize >= std::mem::size_of::<inotify_event>());
        let event = &*(buf.as_ptr() as *const inotify_event);
        assert!(event.mask & IN_MODIFY != 0);

        libc::close(fd);
        std::fs::remove_file(&path).unwrap();
    }
}
