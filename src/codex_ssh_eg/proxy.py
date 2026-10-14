"""Loopback HTTP proxy that relays connections through a SOCKS5 endpoint."""

from __future__ import annotations

import argparse
import ipaddress
import select
import socket
import socketserver
import sys
from typing import Optional, Tuple
from urllib.parse import urlsplit

from .socks5 import connect_via_socks5

MAX_HEADER_BYTES = 64 * 1024


def _parse_authority(authority: str, default_port: Optional[int] = None) -> Tuple[str, int]:
    parsed = urlsplit("//" + authority)
    if not parsed.hostname:
        raise ValueError("missing destination host")
    try:
        port = parsed.port or default_port
    except ValueError as exc:
        raise ValueError("invalid destination port") from exc
    if port is None or not 1 <= port <= 65535:
        raise ValueError("destination port is required")
    return parsed.hostname, port


def relay(left: socket.socket, right: socket.socket) -> None:
    peers = [left, right]
    while True:
        readable, _, exceptional = select.select(peers, [], peers)
        if exceptional:
            return
        for source in readable:
            try:
                payload = source.recv(64 * 1024)
                if not payload:
                    return
                destination = right if source is left else left
                destination.sendall(payload)
            except (ConnectionError, OSError):
                return


class ProxyHandler(socketserver.BaseRequestHandler):
    server: "ProxyServer"

    def _read_headers(self) -> Tuple[bytes, bytes]:
        data = b""
        while b"\r\n\r\n" not in data:
            part = self.request.recv(8192)
            if not part:
                raise ConnectionError("client disconnected while sending headers")
            data += part
            if len(data) > MAX_HEADER_BYTES:
                raise ValueError("request headers are too large")
        header, remainder = data.split(b"\r\n\r\n", 1)
        return header, remainder

    def _send_error(self, status: str) -> None:
        body = (status + "\n").encode("ascii")
        response = (
            f"HTTP/1.1 {status}\r\n"
            f"Content-Length: {len(body)}\r\n"
            "Connection: close\r\n"
            "Content-Type: text/plain\r\n\r\n"
        ).encode("ascii")
        self.request.sendall(response + body)

    def handle(self) -> None:
        upstream: Optional[socket.socket] = None
        try:
            header, remainder = self._read_headers()
            lines = header.split(b"\r\n")
            request_line = lines[0].decode("iso-8859-1").split(" ")
            if len(request_line) != 3:
                raise ValueError("malformed HTTP request line")
            method, target, version = request_line
            if not version.startswith("HTTP/"):
                raise ValueError("invalid HTTP version")

            if method.upper() == "CONNECT":
                host, port = _parse_authority(target)
                upstream = connect_via_socks5(
                    self.server.socks_address, (host, port), self.server.connect_timeout
                )
                self.request.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                if remainder:
                    upstream.sendall(remainder)
            else:
                parsed = urlsplit(target)
                if parsed.scheme not in {"http", "https"} or not parsed.hostname:
                    raise ValueError("proxy requests must use an absolute HTTP URL")
                port = parsed.port or (443 if parsed.scheme == "https" else 80)
                path = parsed.path or "/"
                if parsed.query:
                    path += "?" + parsed.query
                upstream = connect_via_socks5(
                    self.server.socks_address,
                    (parsed.hostname, port),
                    self.server.connect_timeout,
                )
                filtered = [
                    line
                    for line in lines[1:]
                    if not line.lower().startswith(b"proxy-connection:")
                ]
                upstream.sendall(
                    f"{method} {path} {version}\r\n".encode("iso-8859-1")
                    + b"\r\n".join(filtered)
                    + b"\r\n\r\n"
                    + remainder
                )
            relay(self.request, upstream)
        except ValueError:
            self._send_error("400 Bad Request")
        except (ConnectionError, OSError):
            try:
                self._send_error("502 Bad Gateway")
            except OSError:
                pass
        finally:
            if upstream is not None:
                upstream.close()


class ProxyServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(
        self,
        listen_address: Tuple[str, int],
        socks_address: Tuple[str, int],
        connect_timeout: float = 20.0,
    ) -> None:
        self.socks_address = socks_address
        self.connect_timeout = connect_timeout
        super().__init__(listen_address, ProxyHandler)


def _loopback_only(host: str) -> bool:
    try:
        addresses = socket.getaddrinfo(host, None)
    except socket.gaierror:
        return False
    return bool(addresses) and all(
        ipaddress.ip_address(item[4][0]).is_loopback for item in addresses
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Relay a loopback HTTP proxy through a SOCKS5 endpoint."
    )
    parser.add_argument("--listen-host", default="127.0.0.1")
    parser.add_argument("--listen-port", type=int, default=17898)
    parser.add_argument("--socks-host", default="127.0.0.1")
    parser.add_argument("--socks-port", type=int, default=10809)
    parser.add_argument("--connect-timeout", type=float, default=20.0)
    parser.add_argument(
        "--allow-non-loopback",
        action="store_true",
        help="allow a non-loopback listener (unsafe without separate access controls)",
    )
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    for label, port in (("listen", args.listen_port), ("SOCKS", args.socks_port)):
        if not 1 <= port <= 65535:
            print(f"{label} port is out of range", file=sys.stderr)
            return 2
    if not args.allow_non_loopback and not _loopback_only(args.listen_host):
        print("refusing non-loopback listener; use --allow-non-loopback explicitly", file=sys.stderr)
        return 2

    with ProxyServer(
        (args.listen_host, args.listen_port),
        (args.socks_host, args.socks_port),
        args.connect_timeout,
    ) as server:
        print(
            f"HTTP proxy listening on {args.listen_host}:{args.listen_port}; "
            f"SOCKS5 upstream {args.socks_host}:{args.socks_port}",
            flush=True,
        )
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
