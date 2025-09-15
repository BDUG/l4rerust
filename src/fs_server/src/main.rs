//! A basic filesystem server exposing FAT32 operations via L4 IPC.
//!
//! This example demonstrates how a filesystem service could be implemented
//! using the L4Re libraries.  The implementation is intentionally minimal and
//! mainly aims to show how such a server could be structured in Rust.

use fatfs::{FileSystem, FsOptions};
use l4re::sys::{l4re_env, l4re_env_get_cap};
use l4_sys::{l4_ipc_error, l4_msgtag, l4_utcb, l4_utcb_br};
use slab::Slab;
use std::cmp::min;
use std::io::{Read, Seek, SeekFrom, Write};

/// POSIX error numbers for reporting back to clients.
use libc::{EBADF, EIO, ENOENT};

const BR_WORDS: usize = l4_sys::consts::UtcbConsts::L4_UTCB_GENERIC_BUFFERS_SIZE as usize;
const BR_DATA_MAX: usize = BR_WORDS * 8 - 8; // reserve first word for length

/// Read a byte vector from buffer registers. First word contains length.
unsafe fn br_read_bytes() -> Vec<u8> {
    let br = &(*l4_utcb_br()).br;
    let len = min(br[0] as usize, BR_DATA_MAX);
    let ptr = br.as_ptr().add(1) as *const u8;
    let slice = std::slice::from_raw_parts(ptr, len);
    slice.to_vec()
}

/// Read a UTF-8 path string from buffer registers.
unsafe fn br_read_path() -> Option<String> {
    let data = br_read_bytes();
    std::str::from_utf8(&data).ok().map(|s| s.to_owned())
}

/// Write a byte slice into buffer registers.
unsafe fn br_write_bytes(data: &[u8]) {
    let br = &mut (*l4_utcb_br()).br;
    let len = min(data.len(), BR_DATA_MAX);
    br[0] = len as u64;
    let dst = br.as_mut_ptr().add(1) as *mut u8;
    std::ptr::copy_nonoverlapping(data.as_ptr(), dst, len);
}

/// Resolve LSB style paths to FAT paths. Supports /bin, /etc and /usr.
fn resolve_path(p: &str) -> Option<String> {
    if !p.starts_with('/') {
        return None;
    }
    let rel = &p[1..];
    if rel.starts_with("bin/") || rel.starts_with("etc/") || rel.starts_with("usr/") {
        Some(rel.to_string())
    } else {
        None
    }
}

fn io_to_errno(e: std::io::ErrorKind) -> i32 {
    match e {
        std::io::ErrorKind::NotFound => ENOENT,
        _ => EIO,
    }
}

mod virtio;
use virtio::VirtioDisk;

fn main() {
    unsafe { run(); }
}

/// Unsafe portion of the server.  Interacts directly with L4 system calls.
unsafe fn run() {
    // Allocate and register our IPC gate capability under the name "global_fs".
    // In a real system this would require creating a gate and exporting it to
    // the environment.  For the purpose of this repository we merely obtain
    // the gate from the environment if it already exists.
    let gate = l4re_env_get_cap("global_fs").expect("IPC gate 'global_fs' not provided");

    // Bind the gate to our main thread so clients can contact us.
    let gatelabel = 0b1111_0000u64;
    if l4_ipc_error(
        l4::l4_rcv_ep_bind_thread(gate, (*l4re_env()).main_thread, gatelabel),
        l4_utcb(),
    ) != 0
    {
        panic!("failed to bind IPC gate");
    }

    // Initialise the virtio block driver. The driver provides sector based
    // access to the backing store which is consumed by the FAT32 layer.
    let disk = unsafe { VirtioDisk::new().expect("virtio-blk device not available") };
    let fs = FileSystem::new(disk, FsOptions::new()).expect("failed to mount FAT32 volume");
    // Leak filesystem to obtain 'static references for open file handles.
    let fs: &'static FileSystem<VirtioDisk> = Box::leak(Box::new(fs));
    let mut handles: Slab<fatfs::File<'static, VirtioDisk>> = Slab::new();

    // Ready to serve requests.
    println!("filesystem server ready");

    // IPC loop handling filesystem calls.
    let mut label = 0u64;
    let mut tag = l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 });
    loop {
        if l4_ipc_error(tag, l4_utcb()) != 0 {
            tag = l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 });
            continue;
        }

        let mr = unsafe { &mut (*l4::l4_utcb_mr()).mr };
        match mr[0] {
            // Operation 0: list root directory entries.  The server returns the
            // number of entries in MR0.
            0 => {
                let mut count = 0usize;
                for _e in fs.root_dir().iter() { count += 1; }
                mr[0] = count as u64;
            }
            // 1: open file. Path string in buffer registers. Returns descriptor.
            1 => {
                let path = unsafe { br_read_path() };
                if let Some(p) = path.and_then(|p| resolve_path(&p)) {
                    match fs.root_dir().create_file(&p) {
                        Ok(f) => {
                            let fd = handles.insert(f);
                            mr[0] = fd as u64;
                        }
                        Err(e) => {
                            mr[0] = (-(io_to_errno(e.kind()) as i64)) as u64;
                        }
                    }
                } else {
                    mr[0] = (-(ENOENT as i64)) as u64;
                }
            }
            // 2: read from descriptor. MR1=fd, MR2=len. Data returned in BRs.
            2 => {
                let fd = mr[1] as usize;
                let len = mr[2] as usize;
                if handles.contains(fd) {
                    let file = &mut handles[fd];
                    let mut buf = vec![0u8; min(len, BR_DATA_MAX)];
                    match file.read(&mut buf) {
                        Ok(n) => {
                            unsafe { br_write_bytes(&buf[..n]); }
                            mr[0] = n as u64;
                        }
                        Err(e) => {
                            mr[0] = (-(io_to_errno(e.kind()) as i64)) as u64;
                        }
                    }
                } else {
                    mr[0] = (-(EBADF as i64)) as u64;
                }
            }
            // 3: write to descriptor. MR1=fd, data in BRs.
            3 => {
                let fd = mr[1] as usize;
                if handles.contains(fd) {
                    let file = &mut handles[fd];
                    let data = unsafe { br_read_bytes() };
                    match file.write(&data) {
                        Ok(n) => mr[0] = n as u64,
                        Err(e) => mr[0] = (-(io_to_errno(e.kind()) as i64)) as u64,
                    }
                } else {
                    mr[0] = (-(EBADF as i64)) as u64;
                }
            }
            // 4: close descriptor. MR1=fd.
            4 => {
                let fd = mr[1] as usize;
                if handles.contains(fd) {
                    handles.remove(fd);
                    mr[0] = 0;
                } else {
                    mr[0] = (-(EBADF as i64)) as u64;
                }
            }
            // 5: stat path. Path string in BRs, file size returned in MR1.
            5 => {
                let path = unsafe { br_read_path() };
                if let Some(p) = path.and_then(|p| resolve_path(&p)) {
                    match fs.root_dir().open_file(&p) {
                        Ok(mut f) => {
                            if let Ok(size) = f.seek(SeekFrom::End(0)) {
                                mr[0] = 0;
                                mr[1] = size as u64;
                            } else {
                                mr[0] = (-(EIO as i64)) as u64;
                            }
                        }
                        Err(e) => mr[0] = (-(io_to_errno(e.kind()) as i64)) as u64,
                    }
                } else {
                    mr[0] = (-(ENOENT as i64)) as u64;
                }
            }
            // unknown operation
            _ => {
                mr[0] = (-(ENOENT as i64)) as u64;
            }
        }

        // Reply to the client and wait for the next request.
        tag = l4::l4_ipc_reply_and_wait(
            l4_utcb(),
            l4_msgtag(0, 2, 0, 0),
            &mut label,
            l4::l4_timeout_t { raw: 0 },
        );
    }
}
