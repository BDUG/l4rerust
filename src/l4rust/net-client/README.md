# net-client

Minimal client-side helpers for the `global_net` network service.  The
`NetClient` type obtains the IPC gate capability from the L4Re
environment and provides tiny wrappers around the message register
protocol.

## Example

```rust
use net_client::NetClient;

let net = NetClient::new().expect("network service not available");
let sock = net.open_socket().expect("open failed");
net.send(sock, 0xdead_beef).expect("send failed");
let word = net.recv(sock).expect("recv failed");
net.close(sock).expect("close failed");
```

The message format is intentionally small and is expected to evolve as
the network server grows more features.
