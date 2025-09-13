#![no_std]

use core::ffi::c_char;
#[no_mangle]
pub extern "C" fn printk(_fmt: *const c_char, _args: ...) {
    // Stub: ignore kernel print statements
}

#[no_mangle]
pub extern "C" fn module_init(_init: extern "C" fn() -> i32) {
    // Stub: immediately invoke init function
    let _ = _init();
}

#[no_mangle]
pub extern "C" fn module_exit(_exit: extern "C" fn()) {
    // Stub: invoke exit function on module unload
    _exit();
}
