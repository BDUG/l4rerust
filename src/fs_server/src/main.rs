//! A basic filesystem server exposing FAT32 operations via L4 IPC.
//!
//! This example demonstrates how a filesystem service could be implemented
//! using the L4Re libraries.  The implementation is intentionally minimal and
//! mainly aims to show how such a server could be structured in Rust.

use fatfs::{FileSystem, FsOptions};
use l4re::sys::{l4re_env, l4re_env_get_cap};
use l4_sys::{l4_ipc_error, l4_msgtag, l4_utcb};

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

    // Ready to serve requests.
    println!("filesystem server ready");

    // Simple IPC loop handling basic operations.  Clients place the desired
    // operation in message register 0.  Additional arguments would be encoded
    // in further registers or in the buffer registers.  For brevity only a
    // directory listing operation is implemented.
    let mut label = 0u64;
    let mut tag = l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 });
    loop {
        if l4_ipc_error(tag, l4_utcb()) != 0 {
            // Wait again on IPC errors.
            tag = l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 });
            continue;
        }

        match (*l4::l4_utcb_mr()).mr[0] {
            // Operation 0: list root directory entries.  The server returns the
            // number of entries in MR0.  A real implementation would transfer
            // names via buffer registers.
            0 => {
                let mut count = 0usize;
                for _entry in fs.root_dir().iter() {
                    count += 1;
                }
                (*l4::l4_utcb_mr()).mr[0] = count as u64;
            }
            // Placeholder for additional operations such as open, read and
            // write.  These would decode arguments from the message registers
            // and operate on the mounted filesystem accordingly.
            _ => {
                (*l4::l4_utcb_mr()).mr[0] = u64::MAX; // signal unsupported op
            }
        }

        // Reply to the client and wait for the next request.
        tag = l4::l4_ipc_reply_and_wait(
            l4_utcb(),
            l4_msgtag(0, 1, 0, 0),
            &mut label,
            l4::l4_timeout_t { raw: 0 },
        );
    }
}
