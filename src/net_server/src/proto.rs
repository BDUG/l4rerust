//! Message register layout for the simple network protocol.
//!
//! The network service communicates via L4 IPC message registers as
//! follows:
//!
//! ```text
//! MR0: operation
//!     0 = open
//!     1 = send
//!     2 = recv
//!     3 = close
//! MR1: socket handle (except for open)
//! MR2: length / buffer size (send/recv)
//! MR3..: payload data
//! ```
//!
//! Replies reuse the same layout with `MR0` carrying either a new socket
//! handle (for open) or a status/length field for other operations.

pub const OP_OPEN: u64 = 0;
pub const OP_SEND: u64 = 1;
pub const OP_RECV: u64 = 2;
pub const OP_CLOSE: u64 = 3;
