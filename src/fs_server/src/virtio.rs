use l4re::sys::l4re_env_get_cap;
use l4_sys::{l4_cap_idx_t, l4_utcb};

// Constants for a very small virtqueue. Real devices often support much
// larger queues.  Eight entries suffice for demonstration purposes and keep
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

// Request header as defined by the virtio block specification.
#[repr(C)]
struct VirtioBlkReq {
    req_type: u32,
    reserved: u32,
    sector: u64,
}

/// Minimal virtio-blk driver.  The implementation only models the data
/// structures required to submit requests and wait for their completion.
/// It intentionally omits error handling and device negotiation which would
/// be required for a production ready driver.
pub struct VirtioBlk {
    device: l4_cap_idx_t,
    irq: l4_cap_idx_t,
    queue: VirtQueue,
}

impl VirtioBlk {
    /// Initialise the driver by fetching the device and IRQ capabilities from
    /// the L4Re environment.  The capabilities are expected under the names
    /// `virtio_blk` and `virtio_blk_irq` respectively.
    pub unsafe fn new() -> Option<Self> {
        let device = l4re_env_get_cap("virtio_blk")?;
        let irq = l4re_env_get_cap("virtio_blk_irq")?;
        Some(Self { device, irq, queue: VirtQueue::new() })
    }

    /// Submit a read request for the given sector and copy the data into `buf`.
    pub fn read_sector(&mut self, sector: u64, buf: &mut [u8]) -> Result<(), ()> {
        unsafe { self.transfer(sector, buf, true) }
    }

    /// Submit a write request for the given sector from `buf`.
    pub fn write_sector(&mut self, sector: u64, buf: &[u8]) -> Result<(), ()> {
        // We copy the data into a temporary buffer so that the transfer routine
        // can operate on a mutable slice regardless of direction.
        let mut tmp = buf.to_vec();
        unsafe { self.transfer(sector, &mut tmp, false) }
    }

    unsafe fn transfer(&mut self, sector: u64, buf: &mut [u8], read: bool) -> Result<(), ()> {
        let mut header = VirtioBlkReq { req_type: if read { 0 } else { 1 }, reserved: 0, sector };
        let mut status: u8 = 0;

        // Descriptor 0: request header
        self.queue.desc[0] = VirtqDesc {
            addr: &header as *const _ as u64,
            len: core::mem::size_of::<VirtioBlkReq>() as u32,
            flags: 0x0002, // next
            next: 1,
        };

        // Descriptor 1: data buffer
        let mut flags = 0x0002; // next
        if read { flags |= 0x0001; } // write-only for the device
        self.queue.desc[1] = VirtqDesc {
            addr: buf.as_mut_ptr() as u64,
            len: buf.len() as u32,
            flags,
            next: 2,
        };

        // Descriptor 2: status byte written by the device
        self.queue.desc[2] = VirtqDesc {
            addr: &mut status as *mut _ as u64,
            len: 1,
            flags: 0x0001, // device writes
            next: 0,
        };

        // Place descriptor chain into the available ring
        let idx = self.queue.avail.idx as usize % QUEUE_SIZE;
        self.queue.avail.ring[idx] = 0;
        self.queue.avail.idx = self.queue.avail.idx.wrapping_add(1);

        // In a real driver we would notify the device here, e.g. via MMIO.
        // For this demonstrator there is no actual device, so the notification
        // step is left empty.

        // Wait for completion by receiving an interrupt message.  Any message
        // on the IRQ capability is interpreted as completion.
        let mut label = 0u64;
        let _ = l4::l4_ipc_receive(self.irq, l4_utcb(), l4::l4_timeout_t { raw: 0 });
        let _ = l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 });

        if status == 0 {
            Ok(())
        } else {
            Err(())
        }
    }
}

use std::io::{Read, Seek, SeekFrom, Write};

/// Wrapper implementing the `Read`, `Write` and `Seek` traits on top of the
/// sector based virtio driver.  The FAT32 layer consumes this interface when
/// mounting the filesystem.
pub struct VirtioDisk {
    driver: VirtioBlk,
    pos: u64,
    sector_size: usize,
}

impl VirtioDisk {
    pub unsafe fn new() -> Option<Self> {
        let driver = VirtioBlk::new()?;
        Some(Self { driver, pos: 0, sector_size: 512 })
    }
}

impl Read for VirtioDisk {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        let mut done = 0;
        while done < buf.len() {
            let sector = self.pos / self.sector_size as u64;
            let offset = (self.pos as usize) % self.sector_size;
            let mut blk = [0u8; 512];
            self.driver
                .read_sector(sector, &mut blk)
                .map_err(|_| std::io::ErrorKind::Other)?;
            let count = core::cmp::min(self.sector_size - offset, buf.len() - done);
            buf[done..done + count].copy_from_slice(&blk[offset..offset + count]);
            self.pos += count as u64;
            done += count;
        }
        Ok(done)
    }
}

impl Write for VirtioDisk {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let mut done = 0;
        while done < buf.len() {
            let sector = self.pos / self.sector_size as u64;
            let offset = (self.pos as usize) % self.sector_size;
            let mut blk = [0u8; 512];
            if offset != 0 || buf.len() - done < self.sector_size {
                // read-modify-write when partial sector is affected
                self.driver
                    .read_sector(sector, &mut blk)
                    .map_err(|_| std::io::ErrorKind::Other)?;
            }
            let count = core::cmp::min(self.sector_size - offset, buf.len() - done);
            blk[offset..offset + count].copy_from_slice(&buf[done..done + count]);
            self.driver
                .write_sector(sector, &blk)
                .map_err(|_| std::io::ErrorKind::Other)?;
            self.pos += count as u64;
            done += count;
        }
        Ok(done)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

impl Seek for VirtioDisk {
    fn seek(&mut self, pos: SeekFrom) -> std::io::Result<u64> {
        let new = match pos {
            SeekFrom::Start(off) => off as i64,
            SeekFrom::Current(off) => self.pos as i64 + off,
            SeekFrom::End(_) => return Err(std::io::ErrorKind::Unsupported.into()),
        };
        if new < 0 {
            return Err(std::io::ErrorKind::InvalidInput.into());
        }
        self.pos = new as u64;
        Ok(self.pos)
    }
}
