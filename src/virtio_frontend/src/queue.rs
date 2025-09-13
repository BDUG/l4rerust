/// Structures implementing a very small virtqueue similar to the ones used in
/// existing server implementations.

const QUEUE_SIZE: usize = 8;

#[repr(C)]
#[derive(Copy, Clone, Default)]
pub struct VirtqDesc {
    pub addr: u64,
    pub len: u32,
    pub flags: u16,
    pub next: u16,
}

#[repr(C)]
pub struct VirtqAvail {
    pub flags: u16,
    pub idx: u16,
    pub ring: [u16; QUEUE_SIZE],
    pub used_event: u16,
}

#[repr(C)]
#[derive(Copy, Clone, Default)]
pub struct VirtqUsedElem {
    pub id: u32,
    pub len: u32,
}

#[repr(C)]
pub struct VirtqUsed {
    pub flags: u16,
    pub idx: u16,
    pub ring: [VirtqUsedElem; QUEUE_SIZE],
    pub avail_event: u16,
}

/// Simple descriptor ring for demonstration purposes.
pub struct VirtQueue {
    pub desc: [VirtqDesc; QUEUE_SIZE],
    pub avail: VirtqAvail,
    pub used: VirtqUsed,
}

impl VirtQueue {
    pub const fn new() -> Self {
        const DESC: VirtqDesc = VirtqDesc {
            addr: 0,
            len: 0,
            flags: 0,
            next: 0,
        };
        const USED_ELEM: VirtqUsedElem = VirtqUsedElem { id: 0, len: 0 };
        Self {
            desc: [DESC; QUEUE_SIZE],
            avail: VirtqAvail {
                flags: 0,
                idx: 0,
                ring: [0; QUEUE_SIZE],
                used_event: 0,
            },
            used: VirtqUsed {
                flags: 0,
                idx: 0,
                ring: [USED_ELEM; QUEUE_SIZE],
                avail_event: 0,
            },
        }
    }

    /// Place a descriptor chain into the available ring. The descriptors are
    /// copied into the descriptor table starting at index 0.
    pub fn add(&mut self, chain: &[VirtqDesc]) -> Result<u16, ()> {
        if chain.len() > QUEUE_SIZE {
            return Err(());
        }
        for (i, d) in chain.iter().enumerate() {
            self.desc[i] = *d;
        }
        let idx = self.avail.idx as usize % QUEUE_SIZE;
        self.avail.ring[idx] = 0;
        self.avail.idx = self.avail.idx.wrapping_add(1);
        Ok(idx as u16)
    }
}
