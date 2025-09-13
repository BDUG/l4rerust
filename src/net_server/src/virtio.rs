use l4re::sys::l4re_env_get_cap;
use l4_sys::l4_cap_idx_t;

/// Minimal skeleton for a virtio-net driver. The implementation only
/// fetches device capabilities from the L4Re environment and provides
/// stub send/receive methods. A real driver would manage descriptor
/// rings and interact with the device via MMIO.
pub struct VirtioNet {
    device: l4_cap_idx_t,
    irq: l4_cap_idx_t,
}

impl VirtioNet {
    /// Create a new driver instance by obtaining the virtio-net device and
    /// its IRQ capability from the environment. The capabilities are expected
    /// under the names `virtio_net` and `virtio_net_irq` respectively.
    pub unsafe fn new() -> Option<Self> {
        let device = l4re_env_get_cap("virtio_net")?;
        let irq = l4re_env_get_cap("virtio_net_irq")?;
        Some(Self { device, irq })
    }

    /// Send a packet to the network device. Currently this is a stub that
    /// simply pretends success.
    pub fn send(&mut self, _data: &[u8]) -> Result<(), ()> {
        Ok(())
    }

    /// Receive a packet into the provided buffer. Returns the number of
    /// bytes received on success. This stub always indicates that no data
    /// was received.
    pub fn recv(&mut self, _buf: &mut [u8]) -> Result<usize, ()> {
        Err(())
    }
}
