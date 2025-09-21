use libc::{self, c_void};
use std::{ffi::CString, mem, ptr};

#[test]
fn dlsym_resolves_eventfd() {
    unsafe {
        // Use a known libc symbol to validate the staged glibc can be loaded.
        let handle = libc::dlopen(ptr::null(), libc::RTLD_NOW);
        assert!(!handle.is_null(), "dlopen(NULL) returned NULL");

        let symbol = CString::new("eventfd").expect("symbol name");
        let sym = libc::dlsym(handle, symbol.as_ptr());
        assert!(
            !sym.is_null(),
            "dlsym failed to locate eventfd symbol via staged glibc"
        );

        // Touch the symbol via an indirect call to ensure it can be invoked.
        let func: unsafe extern "C" fn(libc::c_uint, libc::c_int) -> libc::c_int =
            mem::transmute::<*mut c_void, _>(sym);
        let fd = func(0, 0);
        assert!(fd >= 0, "eventfd call via dlsym returned an error");
        libc::close(fd);

        libc::dlclose(handle);
    }
}
