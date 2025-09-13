//! A basic driver server linking a standalone driver with the virtio frontend.
//!
//! This server exposes a tiny IPC interface allowing clients to query and
//! configure the virtio transport used by the driver.  It demonstrates how to
//! combine the standalone driver crate with the virtio frontend and L4 IPC.

use core::ffi::c_char;
use driver::start_driver;
use l4re::sys::{l4re_env, l4re_env_get_cap};
use l4_sys::{l4_cap_idx_t, l4_ipc_error, l4_msgtag, l4_utcb};
use std::ffi::CString;
use virtio_frontend::transport::VirtioTransport;

/// FFI for registering an object with the L4Re naming service.
extern "C" {
    fn l4re_ns_register_obj(ns: l4_cap_idx_t, obj: l4_cap_idx_t, name: *const c_char) -> i32;
}

/// Register the provided IPC gate capability under the given name.
unsafe fn register_with_ns(name: &str, gate: l4_cap_idx_t) {
    let ns = l4re_env_get_cap("names").expect("naming service unavailable");
    let cname = CString::new(name).unwrap();
    let ret = l4re_ns_register_obj(ns, gate, cname.as_ptr());
    if ret != 0 {
        panic!("failed to register server: {}", ret);
    }
}

fn main() {
    unsafe { run() }
}

/// Unsafe portion of the server interacting with L4 system calls.
unsafe fn run() {
    // Obtain IPC gate capability for this server.
    let gate = l4re_env_get_cap("driver_srv").expect("IPC gate 'driver_srv' not provided");

    // Bind gate to current thread so clients can communicate with us.
    let gatelabel = 0b1111_0000u64;
    if l4_ipc_error(
        l4::l4_rcv_ep_bind_thread(gate, (*l4re_env()).main_thread, gatelabel),
        l4_utcb(),
    ) != 0
    {
        panic!("failed to bind IPC gate");
    }

    // Register our gate with the naming service for discovery by clients.
    register_with_ns("driver_service", gate);

    // Initialise the standalone driver and virtio transport.
    start_driver();
    let mut transport = VirtioTransport::new(0, 8);

    println!("driver server ready");

    // IPC loop handling simple transport operations.
    let mut label = 0u64;
    let mut tag = l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 });
    loop {
        if l4_ipc_error(tag, l4_utcb()) != 0 {
            tag = l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 });
            continue;
        }

        let mr = &mut (*l4::l4_utcb_mr()).mr;
        match mr[0] {
            // 0: return device feature bitmap.
            0 => {
                mr[0] = transport.device_features;
            }
            // 1: negotiate features with driver. Driver-supported features in MR1.
            1 => {
                let negotiated = transport.negotiate_features(mr[1]);
                mr[0] = negotiated;
            }
            // 2: write 32-bit value to config space. MR1=offset, MR2=value.
            2 => {
                let off = mr[1] as usize;
                let val = mr[2].to_le_bytes();
                transport.write_config(off, &val[..4]);
                mr[0] = 0;
            }
            // 3: read 32-bit value from config space. MR1=offset, result in MR0.
            3 => {
                let off = mr[1] as usize;
                let mut buf = [0u8; 4];
                transport.read_config(off, &mut buf);
                mr[0] = u32::from_le_bytes(buf) as u64;
            }
            _ => {
                mr[0] = u64::MAX;
            }
        }

        tag = l4::l4_ipc_reply_and_wait(
            l4_utcb(),
            l4_msgtag(0, 1, 0, 0),
            &mut label,
            l4::l4_timeout_t { raw: 0 },
        );
    }
}

