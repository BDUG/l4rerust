//! A basic network server exposing packet operations via L4 IPC.
//!
//! This server demonstrates how a network service could be structured in
//! Rust using the L4Re libraries. The implementation is intentionally
//! minimal and mainly focuses on the IPC setup and loop.

use l4re::sys::{l4re_env, l4re_env_get_cap};
use l4_sys::{l4_ipc_error, l4_msgtag, l4_utcb};

// smoltcp imports for network stack handling
use smoltcp::iface::{Config, Interface, SocketSet, SocketStorage};
use smoltcp::phy::{Device, DeviceCapabilities, Medium, RxToken, TxToken};
use smoltcp::socket::{udp, TcpSocket, TcpSocketBuffer, UdpSocket, UdpSocketBuffer};
use smoltcp::time::Instant;
use smoltcp::wire::{EthernetAddress, IpAddress, IpEndpoint, Ipv4Address, Ipv4Cidr};

mod virtio;
use virtio::VirtioNet;

// Adapter implementing smoltcp's `Device` trait on top of the simple
// virtio-net driver.
struct VirtioDevice<'a> {
    net: &'a mut VirtioNet,
}

struct VirtioRxToken<'a> {
    net: &'a mut VirtioNet,
}

struct VirtioTxToken<'a> {
    net: &'a mut VirtioNet,
}

impl<'a> Device for VirtioDevice<'a> {
    type RxToken<'b> = VirtioRxToken<'b> where Self: 'b;
    type TxToken<'b> = VirtioTxToken<'b> where Self: 'b;

    fn receive(&mut self, _timestamp: Instant) -> Option<(Self::RxToken<'_>, Self::TxToken<'_>)> {
        Some((VirtioRxToken { net: self.net }, VirtioTxToken { net: self.net }))
    }

    fn transmit(&mut self, _timestamp: Instant) -> Option<Self::TxToken<'_>> {
        Some(VirtioTxToken { net: self.net })
    }

    fn capabilities(&self) -> DeviceCapabilities {
        let mut caps = DeviceCapabilities::default();
        caps.max_transmission_unit = 1514;
        caps.max_burst_size = Some(1);
        caps.medium = Medium::Ethernet;
        caps
    }
}

impl<'a> RxToken for VirtioRxToken<'a> {
    fn consume<R, F>(self, f: F) -> R
    where
        F: FnOnce(&[u8]) -> R,
    {
        let mut buf = [0u8; 1536];
        let len = self.net.receive_frame(&mut buf).unwrap_or(0);
        f(&buf[..len])
    }
}

impl<'a> TxToken for VirtioTxToken<'a> {
    fn consume<R, F>(self, len: usize, f: F) -> R
    where
        F: FnOnce(&mut [u8]) -> R,
    {
        let mut buf = vec![0u8; len];
        let res = f(&mut buf[..]);
        let _ = self.net.send_frame(&buf[..]);
        res
    }
}

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

    // Initialise the virtio network driver and wrap it for smoltcp.
    let mut net = unsafe { VirtioNet::new().expect("virtio-net device not available") };
    let mut device = VirtioDevice { net: &mut net };

    // Configure interface parameters: MAC address, IP and gateway.
    let mac = EthernetAddress([0x52, 0x54, 0x00, 0x12, 0x34, 0x56]);
    let mut config = Config::new(mac.into());
    let mut iface = Interface::new(config, &mut device, Instant::from_millis(0));
    let ip = Ipv4Address::new(10, 0, 2, 15);
    iface
        .update_ip_addrs(|addrs| addrs.push(Ipv4Cidr::new(ip, 24)).unwrap());
    iface
        .routes_mut()
        .add_default_ipv4_route(Ipv4Address::new(10, 0, 2, 2))
        .unwrap();

    // Prepare a small socket set containing one UDP and one TCP socket.
    let mut sockets_storage: [SocketStorage; 2] = [SocketStorage::EMPTY; 2];
    let mut sockets = SocketSet::new(&mut sockets_storage[..]);

    let udp_rx_meta = [udp::PacketMetadata::EMPTY; 4];
    let udp_rx_buf = [0u8; 512];
    let udp_tx_meta = [udp::PacketMetadata::EMPTY; 4];
    let udp_tx_buf = [0u8; 512];
    let udp_socket = UdpSocket::new(
        UdpSocketBuffer::new(udp_rx_meta, udp_rx_buf),
        UdpSocketBuffer::new(udp_tx_meta, udp_tx_buf),
    );
    let udp_handle = sockets.add(udp_socket);

    let tcp_rx = TcpSocketBuffer::new(vec![0; 1024]);
    let tcp_tx = TcpSocketBuffer::new(vec![0; 1024]);
    let tcp_socket = TcpSocket::new(tcp_rx, tcp_tx);
    let tcp_handle = sockets.add(tcp_socket);

    println!("network server ready");

    // IPC loop handling basic socket requests. Clients encode the operation in
    // message register 0. Additional arguments would normally be placed in
    // further registers or buffers.
    let mut label = 0u64;
    let mut tag = l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 });
    loop {
        if l4_ipc_error(tag, l4_utcb()) != 0 {
            tag = l4::l4_ipc_wait(l4_utcb(), &mut label, l4::l4_timeout_t { raw: 0 });
            continue;
        }

        // Drive the network stack.
        let _ = iface.poll(Instant::from_millis(0), &mut device, &mut sockets);

        match (*l4::l4_utcb_mr()).mr[0] {
            // Operation 0: send an empty UDP packet to a fixed endpoint.
            0 => {
                let mut sock = sockets.get::<UdpSocket>(udp_handle);
                let endpoint = IpEndpoint::new(IpAddress::v4(10, 0, 2, 2), 80);
                let _ = sock.send_slice(&[], endpoint);
                (*l4::l4_utcb_mr()).mr[0] = 0;
            }
            // Operation 1: try to receive a UDP packet, returning its length.
            1 => {
                let mut sock = sockets.get::<UdpSocket>(udp_handle);
                let res = sock.recv().map(|(d, _)| d.len()).unwrap_or(0);
                (*l4::l4_utcb_mr()).mr[0] = res as u64;
            }
            // Operation 2: initiate a TCP connection to a fixed endpoint.
            2 => {
                let mut sock = sockets.get::<TcpSocket>(tcp_handle);
                if !sock.is_open() {
                    let _ = sock.connect(IpEndpoint::new(IpAddress::v4(10, 0, 2, 2), 80), 49500);
                }
                (*l4::l4_utcb_mr()).mr[0] = 0;
            }
            // Operation 3: send an empty TCP packet if the connection is open.
            3 => {
                let mut sock = sockets.get::<TcpSocket>(tcp_handle);
                let _ = sock.send_slice(b"");
                (*l4::l4_utcb_mr()).mr[0] = 0;
            }
            // Operation 4: receive data from the TCP socket, returning the length.
            4 => {
                let mut sock = sockets.get::<TcpSocket>(tcp_handle);
                let mut buf = [0u8; 512];
                let res = sock.recv_slice(&mut buf).unwrap_or(0);
                (*l4::l4_utcb_mr()).mr[0] = res as u64;
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
