use std::ffi::CString;

#[test]
fn musl_libc_available() {
    unsafe {
        let handle = libc::dlopen(std::ptr::null(), libc::RTLD_NOW);
        assert!(
            !handle.is_null(),
            "dlopen returned null handle for musl libc"
        );

        let symbol = CString::new("eventfd").unwrap();
        let ptr = libc::dlsym(handle, symbol.as_ptr());
        assert!(
            !ptr.is_null(),
            "dlsym failed to locate eventfd symbol via staged musl libc"
        );
        libc::dlclose(handle);
    }
}
