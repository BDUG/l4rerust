#![no_std]

extern crate linux_shims;

extern "C" {
    fn l4re_driver_start();
}

#[no_mangle]
pub extern "C" fn start_driver() {
    unsafe {
        l4re_driver_start();
    }
}
