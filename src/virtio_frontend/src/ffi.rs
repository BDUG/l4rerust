use crate::queue::VirtqDesc;
use crate::transport::VirtioTransport;

/// Create a new transport instance for use from C.
#[no_mangle]
pub extern "C" fn virtio_transport_create(
    device_features: u64,
    config_len: usize,
) -> *mut VirtioTransport {
    Box::into_raw(Box::new(VirtioTransport::new(device_features, config_len)))
}

/// Destroy a transport previously created via [`virtio_transport_create`].
#[no_mangle]
pub unsafe extern "C" fn virtio_transport_destroy(transport: *mut VirtioTransport) {
    if !transport.is_null() {
        drop(Box::from_raw(transport));
    }
}

/// Negotiate features using a C ABI.
#[no_mangle]
pub unsafe extern "C" fn virtio_negotiate_features(
    transport: *mut VirtioTransport,
    driver_supported: u64,
) -> u64 {
    (*transport).negotiate_features(driver_supported)
}

/// Read from the configuration space using raw pointers.
#[no_mangle]
pub unsafe extern "C" fn virtio_config_read(
    transport: *const VirtioTransport,
    offset: usize,
    buf: *mut u8,
    len: usize,
) {
    let slice = core::slice::from_raw_parts_mut(buf, len);
    (*transport).read_config(offset, slice);
}

/// Write to the configuration space using raw pointers.
#[no_mangle]
pub unsafe extern "C" fn virtio_config_write(
    transport: *mut VirtioTransport,
    offset: usize,
    buf: *const u8,
    len: usize,
) {
    let slice = core::slice::from_raw_parts(buf, len);
    (*transport).write_config(offset, slice);
}

/// Add a descriptor chain to the transport's queue. Returns 0 on success.
#[no_mangle]
pub unsafe extern "C" fn virtio_queue_add(
    transport: *mut VirtioTransport,
    descs: *const VirtqDesc,
    count: usize,
) -> i32 {
    let slice = core::slice::from_raw_parts(descs, count);
    match (*transport).queue.add(slice) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}
