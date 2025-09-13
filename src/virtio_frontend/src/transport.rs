use crate::queue::VirtQueue;

/// Simple virtio transport exposing feature negotiation, config space access
/// and a single virtqueue.
pub struct VirtioTransport {
    pub device_features: u64,
    pub driver_features: u64,
    config: Vec<u8>,
    pub queue: VirtQueue,
}

impl VirtioTransport {
    /// Create a new transport with the given device features and config space
    /// size in bytes.
    pub fn new(device_features: u64, config_len: usize) -> Self {
        Self {
            device_features,
            driver_features: 0,
            config: vec![0; config_len],
            queue: VirtQueue::new(),
        }
    }

    /// Negotiate features with the driver. Returns the agreed upon feature set.
    pub fn negotiate_features(&mut self, driver_supported: u64) -> u64 {
        let negotiated = self.device_features & driver_supported;
        self.driver_features = negotiated;
        negotiated
    }

    /// Read from the virtual device configuration space.
    pub fn read_config(&self, offset: usize, data: &mut [u8]) {
        assert!(offset + data.len() <= self.config.len());
        data.copy_from_slice(&self.config[offset..offset + data.len()]);
    }

    /// Write to the virtual device configuration space.
    pub fn write_config(&mut self, offset: usize, data: &[u8]) {
        assert!(offset + data.len() <= self.config.len());
        self.config[offset..offset + data.len()].copy_from_slice(data);
    }
}
