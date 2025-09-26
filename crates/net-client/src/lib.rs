#![no_std]

#[cfg(target_os = "l4re")]
mod implementation {
    //! Simple client library for the `global_net` network service.
    //!
    //! # Message register layout
    //!
    //! All operations use the first message register (`MR0`) to denote the
    //! operation code. Additional registers carry operation specific
    //! arguments as documented below:
    //!
    //! ```text
    //! MR0: operation code
    //!
    //! Socket open (OP_OPEN)
    //!   MR1: protocol (0 = UDP)
    //!   Reply: MR0 = socket handle
    //!
    //! Socket send (OP_SEND)
    //!   MR1: socket handle
    //!   MR2: length in bytes
    //!   MR3..: payload (truncated to available registers)
    //!   Reply: MR0 = status (0 = ok)
    //!
    //! Socket receive (OP_RECV)
    //!   MR1: socket handle
    //!   MR2: buffer capacity
    //!   Reply: MR0 = bytes received
    //!   MR1..: payload
    //!
    //! Socket close (OP_CLOSE)
    //!   MR1: socket handle
    //!   Reply: MR0 = status (0 = ok)
    //! ```
    //!
    //! The functions provided here implement these operations for small
    //! messages entirely transmitted via the message registers. They are
    //! intended as a starting point for more fully fledged networking
    //! support.

    use l4re::sys::l4re_env_get_cap;
    use l4::sys::{l4_ipc_call, l4_ipc_error, l4_msgtag, l4_utcb};

    /// Operation code: open a socket.
    pub const OP_OPEN: u64 = 0;
    /// Operation code: send data.
    pub const OP_SEND: u64 = 1;
    /// Operation code: receive data.
    pub const OP_RECV: u64 = 2;
    /// Operation code: close a socket.
    pub const OP_CLOSE: u64 = 3;

    /// Client handle to the network service.
    pub struct NetClient {
        gate: l4re::sys::l4_cap_idx_t,
    }

    impl NetClient {
        /// Retrieve the `global_net` capability from the environment.
        pub fn new() -> Option<Self> {
            l4re_env_get_cap("global_net").map(|gate| NetClient { gate })
        }

        /// Request a UDP socket from the server.
        pub fn open_socket(&self) -> Result<u64, i32> {
            unsafe {
                (*l4::sys::l4_utcb_mr()).mr[0] = OP_OPEN;
                (*l4::sys::l4_utcb_mr()).mr[1] = 0; // protocol: UDP
                let tag = l4_ipc_call(
                    self.gate,
                    l4_utcb(),
                    l4_msgtag(0, 2, 0, 0),
                    l4::sys::l4_timeout_t { raw: 0 },
                );
                let err = l4_ipc_error(tag, l4_utcb());
                if err != 0 {
                    return Err(err);
                }
                Ok((*l4::sys::l4_utcb_mr()).mr[0])
            }
        }

        /// Send a single word of data to the server.
        pub fn send(&self, handle: u64, word: u64) -> Result<(), i32> {
            unsafe {
                (*l4::sys::l4_utcb_mr()).mr[0] = OP_SEND;
                (*l4::sys::l4_utcb_mr()).mr[1] = handle;
                (*l4::sys::l4_utcb_mr()).mr[2] = word;
                let tag = l4_ipc_call(
                    self.gate,
                    l4_utcb(),
                    l4_msgtag(0, 3, 0, 0),
                    l4::sys::l4_timeout_t { raw: 0 },
                );
                let err = l4_ipc_error(tag, l4_utcb());
                if err != 0 {
                    return Err(err);
                }
                Ok(())
            }
        }

        /// Receive a single word of data from the server.
        pub fn recv(&self, handle: u64) -> Result<u64, i32> {
            unsafe {
                (*l4::sys::l4_utcb_mr()).mr[0] = OP_RECV;
                (*l4::sys::l4_utcb_mr()).mr[1] = handle;
                let tag = l4_ipc_call(
                    self.gate,
                    l4_utcb(),
                    l4_msgtag(0, 2, 0, 0),
                    l4::sys::l4_timeout_t { raw: 0 },
                );
                let err = l4_ipc_error(tag, l4_utcb());
                if err != 0 {
                    return Err(err);
                }
                Ok((*l4::sys::l4_utcb_mr()).mr[0])
            }
        }

        /// Close the socket.
        pub fn close(&self, handle: u64) -> Result<(), i32> {
            unsafe {
                (*l4::sys::l4_utcb_mr()).mr[0] = OP_CLOSE;
                (*l4::sys::l4_utcb_mr()).mr[1] = handle;
                let tag = l4_ipc_call(
                    self.gate,
                    l4_utcb(),
                    l4_msgtag(0, 2, 0, 0),
                    l4::sys::l4_timeout_t { raw: 0 },
                );
                let err = l4_ipc_error(tag, l4_utcb());
                if err != 0 {
                    return Err(err);
                }
                Ok(())
            }
        }
    }
}

#[cfg(target_os = "l4re")]
pub use implementation::*;

#[cfg(not(target_os = "l4re"))]
pub struct NetClient;

#[cfg(not(target_os = "l4re"))]
impl NetClient {
    pub fn new() -> Option<Self> {
        None
    }
}

