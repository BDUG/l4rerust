#![cfg_attr(not(test), no_std)]

use core::ffi::{c_char, c_void};
use core::sync::atomic::{AtomicBool, Ordering};

extern "C" {
    fn vprintf(fmt: *const c_char, args: *mut c_void) -> i32;
}

static INIT_DONE: AtomicBool = AtomicBool::new(false);
static mut EXIT_HANDLER: Option<extern "C" fn()> = None;

#[no_mangle]
pub unsafe extern "C" fn printk(fmt: *const c_char, args: *mut c_void) {
    vprintf(fmt, args);
}

#[no_mangle]
pub extern "C" fn module_init(init: extern "C" fn() -> i32) {
    if INIT_DONE
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return;
    }
    if init() != 0 {
        INIT_DONE.store(false, Ordering::SeqCst);
    }
}

#[no_mangle]
pub extern "C" fn module_exit(exit: extern "C" fn()) {
    unsafe {
        if INIT_DONE.load(Ordering::SeqCst) {
            EXIT_HANDLER = Some(exit);
        }
    }
}

#[no_mangle]
pub extern "C" fn module_shutdown() {
    if INIT_DONE.swap(false, Ordering::SeqCst) {
        unsafe {
            if let Some(handler) = EXIT_HANDLER {
                handler();
                EXIT_HANDLER = None;
            }
        }
    }
}
#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::sync::atomic::{AtomicUsize, Ordering};

    static INIT_COUNT: AtomicUsize = AtomicUsize::new(0);
    static EXIT_COUNT: AtomicUsize = AtomicUsize::new(0);

    extern "C" fn init_ok() -> i32 {
        INIT_COUNT.fetch_add(1, Ordering::SeqCst);
        0
    }

    extern "C" fn init_fail() -> i32 {
        INIT_COUNT.fetch_add(1, Ordering::SeqCst);
        1
    }

    extern "C" fn exit_fn() {
        EXIT_COUNT.fetch_add(1, Ordering::SeqCst);
    }

    #[test]
    fn shutdown_runs_exit_on_success() {
        INIT_COUNT.store(0, Ordering::SeqCst);
        EXIT_COUNT.store(0, Ordering::SeqCst);
        module_init(init_ok);
        module_exit(exit_fn);
        module_shutdown();
        assert_eq!(INIT_COUNT.load(Ordering::SeqCst), 1);
        assert_eq!(EXIT_COUNT.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn failed_init_skips_exit() {
        INIT_COUNT.store(0, Ordering::SeqCst);
        EXIT_COUNT.store(0, Ordering::SeqCst);
        module_init(init_fail);
        module_exit(exit_fn);
        module_shutdown();
        assert_eq!(INIT_COUNT.load(Ordering::SeqCst), 1);
        assert_eq!(EXIT_COUNT.load(Ordering::SeqCst), 0);
    }
}
