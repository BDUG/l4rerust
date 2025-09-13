pub mod ffi;
pub mod queue;
pub mod transport;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn feature_negotiation() {
        let mut dev = transport::VirtioTransport::new(0b1010, 0);
        let features = dev.negotiate_features(0b1110);
        assert_eq!(features, 0b1010 & 0b1110);
    }

    #[test]
    fn config_space_rw() {
        let mut dev = transport::VirtioTransport::new(0, 8);
        dev.write_config(2, &[1, 2, 3, 4]);
        let mut buf = [0u8; 4];
        dev.read_config(2, &mut buf);
        assert_eq!(&buf, &[1, 2, 3, 4]);
    }

    #[test]
    fn queue_add_descriptor() {
        let mut dev = transport::VirtioTransport::new(0, 0);
        let descs = [
            queue::VirtqDesc {
                addr: 0x1000,
                len: 16,
                flags: 0x0002,
                next: 1,
            },
            queue::VirtqDesc {
                addr: 0x2000,
                len: 32,
                flags: 0,
                next: 0,
            },
        ];
        dev.queue.add(&descs).unwrap();
        assert_eq!(dev.queue.avail.idx, 1);
        assert_eq!(dev.queue.desc[0].addr, 0x1000);
    }

    #[test]
    fn ffi_roundtrip() {
        unsafe {
            let dev = ffi::virtio_transport_create(0b1, 4);
            let neg = ffi::virtio_negotiate_features(dev, 0b11);
            assert_eq!(neg, 0b1);
            let value = [0xAAu8];
            ffi::virtio_config_write(dev, 0, value.as_ptr(), value.len());
            let mut out = [0u8];
            ffi::virtio_config_read(dev, 0, out.as_mut_ptr(), out.len());
            assert_eq!(out[0], 0xAA);
            ffi::virtio_transport_destroy(dev);
        }
    }
}
