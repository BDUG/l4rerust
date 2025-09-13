//! Example client for the driver server.
//!
//! Demonstrates discovering the server via the L4Re naming service and
//! performing a couple of simple IPC operations.

use l4re::sys::{l4re_env_get_cap, l4_msgtag, l4_utcb};
use l4_sys::l4_ipc_error;

fn main() {
    unsafe {
        // Look up the server by the name it registered.
        let gate = l4re_env_get_cap("driver_service").expect("server not found");

        // Operation 0: query device feature bits.
        let mr = &mut (*l4::l4_utcb_mr()).mr;
        mr[0] = 0;
        let tag = l4::l4_ipc_call(gate, l4_utcb(), l4_msgtag(0, 1, 0, 0), l4::l4_timeout_t { raw: 0 });
        if l4_ipc_error(tag, l4_utcb()) == 0 {
            println!("device features: 0x{:x}", mr[0]);
        } else {
            println!("IPC error querying features");
        }

        // Operation 1: negotiate features with the driver.
        mr[0] = 1;      // operation
        mr[1] = 0x1;    // driver supported features
        let tag = l4::l4_ipc_call(gate, l4_utcb(), l4_msgtag(0, 2, 0, 0), l4::l4_timeout_t { raw: 0 });
        if l4_ipc_error(tag, l4_utcb()) == 0 {
            println!("negotiated features: 0x{:x}", mr[0]);
        } else {
            println!("IPC error during negotiation");
        }
    }
}

