use l4re::sys::l4re_env_get_cap;
use l4_sys::{l4_cap_idx_t, l4_utcb};

// Constants for a very small virtqueue. Real devices often support much
// larger queues. Eight entries suffice for demonstration purposes and keep
// memory usage minimal.
const QUEUE_SIZE: usize = 8;

#[repr(C)]
#[derive(Copy, Clone)]
struct VirtqDesc {
    addr: u64,
    len: u32,
    flags: u16,
    next: u16,
}

#[repr(C)]
struct VirtqAvail {
    flags: u16,
    idx: u16,
    ring: [u16; QUEUE_SIZE],
    used_event: u16,
}

#[repr(C)]
#[derive(Copy, Clone)]
struct VirtqUsedElem {
    id: u32,
    len: u32,
}

#[repr(C)]
struct VirtqUsed {
    flags: u16,
    idx: u16,
    ring: [VirtqUsedElem; QUEUE_SIZE],
    avail_event: u16,
}

// Simple virtqueue descriptor set.
struct VirtQueue {
    desc: [VirtqDesc; QUEUE_SIZE],
    avail: VirtqAvail,
    used: VirtqUsed,
}

impl VirtQueue {
    const fn new() -> Self {
        const DESC: VirtqDesc = VirtqDesc { addr: 0, len: 0, flags: 0, next: 0 };
        const USED_ELEM: VirtqUsedElem = VirtqUsedElem { id: 0, len: 0 };
        Self {
            desc: [DESC; QUEUE_SIZE],
            avail: VirtqAvail { flags: 0, idx: 0, ring: [0; QUEUE_SIZE], used_event: 0 },
            used: VirtqUsed {
                flags: 0,
                idx: 0,
                ring: [USED_ELEM; QUEUE_SIZE],
                avail_event: 0,
            },
        }
    }
}

// Network header as defined by the virtio-net specification without any
// offloading features enabled.
#[repr(C, packed)]
#[derive(Copy, Clone, Default)]
struct VirtioNetHdr {
    flags: u8,
    gso_type: u8,
    hdr_len: u16,
    gso_size: u16,
    csum_start: u16,
    csum_offset: u16,
}

/// Minimal virtio-net driver. The implementation models the data structures
/// required to submit and receive Ethernet frames. It intentionally omits
/// error handling and device negotiation which would be required for a
/// production ready driver.
pub struct VirtioNet {
    device: l4_cap_idx_t,
    irq: l4_cap_idx_t,
    queue: VirtQueue,
}

impl VirtioNet {
    /// Create a new driver instance by obtaining the virtio-net device and
    /// its IRQ capability from the environment. The capabilities are expected
    /// under the names `virtio_net` and `virtio_net_irq` respectively.
    pub unsafe fn new() -> Option<Self> {
        let device = l4re_env_get_cap("virtio_net")?;
        let irq = l4re_env_get_cap("virtio_net_irq")?;
        Some(Self { device, irq, queue: VirtQueue::new() })
    }

    /// Enqueue an Ethernet frame for transmission.
    pub fn send_frame(&mut self, frame: &[u8]) -> Result<(), ()> {
        let header = VirtioNetHdr::default();

        // Descriptor 0: header
        self.queue.desc[0] = VirtqDesc {
            addr: &header as *const _ as u64,
            len: core::mem::size_of::<VirtioNetHdr>() as u32,
            flags: 0x0002, // next
            next: 1,
        };

        // Descriptor 1: frame data
        self.queue.desc[1] = VirtqDesc {
            addr: frame.as_ptr() as u64,
            len: frame.len() as u32,
            flags: 0,
            next: 0,
        };

        // Place descriptor chain into available ring
        let idx = self.queue.avail.idx as usize % QUEUE_SIZE;
        self.queue.avail.ring[idx] = 0;
        self.queue.avail.idx = self.queue.avail.idx.wrapping_add(1);

        // Wait for completion signalled by an interrupt
        let mut label = 0u64;
        let _ = unsafe { l4::l4_ipc_receive(self.irq, l4_utcb(), l4::l4_timeout_t { raw: 0 }) };
        let _ = unsafe { l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 }) };

        Ok(())
    }

    /// Dequeue an Ethernet frame into the provided buffer. Returns the number
    /// of bytes copied into `buf`.
    pub fn receive_frame(&mut self, buf: &mut [u8]) -> Result<usize, ()> {
        let mut header = VirtioNetHdr::default();

        // Descriptor 0: header written by device
        self.queue.desc[0] = VirtqDesc {
            addr: &mut header as *mut _ as u64,
            len: core::mem::size_of::<VirtioNetHdr>() as u32,
            flags: 0x0003, // device writes | next
            next: 1,
        };

        // Descriptor 1: frame buffer written by device
        self.queue.desc[1] = VirtqDesc {
            addr: buf.as_mut_ptr() as u64,
            len: buf.len() as u32,
            flags: 0x0001, // device writes
            next: 0,
        };

        // Make descriptor available
        let idx = self.queue.avail.idx as usize % QUEUE_SIZE;
        self.queue.avail.ring[idx] = 0;
        self.queue.avail.idx = self.queue.avail.idx.wrapping_add(1);

        // Wait for interrupt
        let mut label = 0u64;
        let _ = unsafe { l4::l4_ipc_receive(self.irq, l4_utcb(), l4::l4_timeout_t { raw: 0 }) };
        let _ = unsafe { l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 }) };

        // Determine length from used ring
        let used_idx = self.queue.used.idx.wrapping_sub(1) as usize % QUEUE_SIZE;
        let len = self.queue.used.ring[used_idx].len as usize;
        if len < core::mem::size_of::<VirtioNetHdr>() {
            return Err(());
        }
        Ok(len - core::mem::size_of::<VirtioNetHdr>())
    }
}

