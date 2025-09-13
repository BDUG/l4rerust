//! A basic network server exposing packet operations via L4 IPC.
//!
//! This server demonstrates how a network service could be structured in
//! Rust using the L4Re libraries. The implementation is intentionally
//! minimal and mainly focuses on the IPC setup and loop.

use l4re::sys::{l4re_env, l4re_env_get_cap};
use l4_sys::{l4_ipc_error, l4_msgtag, l4_utcb};

mod virtio;
use virtio::VirtioNet;

fn main() {
    unsafe { run(); }
}

/// Unsafe portion of the server. Interacts directly with L4 system calls.
unsafe fn run() {
    // Obtain the IPC gate capability named "global_net" from the environment.
    let gate = l4re_env_get_cap("global_net").expect("IPC gate 'global_net' not provided");

    // Bind the gate to our main thread so clients can contact us.
    let gatelabel = 0b1111_0000u64;
    if l4_ipc_error(
        l4::l4_rcv_ep_bind_thread(gate, (*l4re_env()).main_thread, gatelabel),
        l4_utcb(),
    ) != 0
    {
        panic!("failed to bind IPC gate");
    }

    // Initialise the virtio network driver. A real implementation would
    // use the driver to send and receive packets.
    let mut net = unsafe { VirtioNet::new().expect("virtio-net device not available") };

    println!("network server ready");

    // IPC loop handling basic network requests. Clients encode the
    // operation in message register 0. Additional arguments would normally
    // be placed in further registers or buffers.
    let mut label = 0u64;
    let mut tag = l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 });
    loop {
        if l4_ipc_error(tag, l4_utcb()) != 0 {
            tag = l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 });
            continue;
        }

        match (*l4::l4_utcb_mr()).mr[0] {
            // Operation 0: send a packet. For demonstration we simply
            // acknowledge the request.
            0 => {
                let _ = net.send_frame(&[]);
                (*l4::l4_utcb_mr()).mr[0] = 0;
            }
            // Operation 1: receive a packet. We currently signal that no
            // data is available.
            1 => {
                let mut buf = [0u8; 0];
                let res = net
                    .receive_frame(&mut buf)
                    .map(|len| len as u64)
                    .unwrap_or(u64::MAX);
                (*l4::l4_utcb_mr()).mr[0] = res;
            }
            // Unsupported operations are indicated with all bits set.
            _ => {
                (*l4::l4_utcb_mr()).mr[0] = u64::MAX;
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
