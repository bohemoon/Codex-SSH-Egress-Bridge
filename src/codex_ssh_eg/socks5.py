"""Minimal SOCKS5 client helpers using only the Python standard library."""

from __future__ import annotations

import ipaddress
import socket
from typing import Tuple


class Socks5Error(OSError):
    """Raised when the SOCKS5 peer rejects or malforms a request."""


def recv_exact(sock: socket.socket, size: int) -> bytes:
    chunks = []
    remaining = size
    while remaining:
        chunk = sock.recv(remaining)
        if not chunk:
            raise Socks5Error("unexpected EOF from SOCKS5 peer")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def _encode_destination(host: str) -> bytes:
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        encoded = host.encode("idna")
        if not encoded or len(encoded) > 255:
            raise Socks5Error("destination hostname length is invalid")
        return b"\x03" + bytes([len(encoded)]) + encoded
    if address.version == 4:
        return b"\x01" + address.packed
    return b"\x04" + address.packed


def _consume_bound_address(sock: socket.socket, address_type: int) -> None:
    if address_type == 1:
        recv_exact(sock, 6)
    elif address_type == 3:
        recv_exact(sock, recv_exact(sock, 1)[0] + 2)
    elif address_type == 4:
        recv_exact(sock, 18)
    else:
        raise Socks5Error(f"unsupported SOCKS5 address type: {address_type}")


def connect_via_socks5(
    proxy: Tuple[str, int], destination: Tuple[str, int], timeout: float = 20.0
) -> socket.socket:
    """Return a TCP socket connected through a no-auth SOCKS5 proxy."""

    host, port = destination
    if not 1 <= port <= 65535:
        raise Socks5Error("destination port is out of range")
    encoded_destination = _encode_destination(host)

    upstream = socket.create_connection(proxy, timeout=timeout)
    try:
        upstream.sendall(b"\x05\x01\x00")
        if recv_exact(upstream, 2) != b"\x05\x00":
            raise Socks5Error("SOCKS5 peer did not accept no-auth mode")

        upstream.sendall(
            b"\x05\x01\x00" + encoded_destination + port.to_bytes(2, "big")
        )
        reply = recv_exact(upstream, 4)
        if reply[0] != 5:
            raise Socks5Error("invalid SOCKS5 reply version")
        if reply[1] != 0:
            raise Socks5Error(f"SOCKS5 CONNECT failed with code {reply[1]}")
        _consume_bound_address(upstream, reply[3])
        return upstream
    except Exception:
        upstream.close()
        raise
