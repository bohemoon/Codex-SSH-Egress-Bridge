"""Layered, credential-free verification for the SSH egress bridge."""

from __future__ import annotations

import argparse
import socket
import ssl
import time

from .socks5 import connect_via_socks5, recv_exact


def _http_connect(proxy, host: str, port: int, timeout: float) -> socket.socket:
    sock = socket.create_connection(proxy, timeout=timeout)
    sock.sendall(
        f"CONNECT {host}:{port} HTTP/1.1\r\nHost: {host}:{port}\r\n\r\n".encode("ascii")
    )
    response = b""
    while b"\r\n\r\n" not in response:
        part = sock.recv(4096)
        if not part:
            raise OSError("unexpected EOF from HTTP proxy")
        response += part
        if len(response) > 64 * 1024:
            raise OSError("HTTP proxy response headers are too large")
    status = response.split(b"\r\n", 1)[0]
    if b" 200 " not in status:
        raise OSError(f"HTTP CONNECT failed: {status.decode('iso-8859-1')}")
    return sock


def _https_status(label, make_socket, host: str, path: str, timeout: float) -> bool:
    started = time.monotonic()
    raw = make_socket()
    try:
        context = ssl.create_default_context()
        with context.wrap_socket(raw, server_hostname=host) as tls:
            tls.settimeout(timeout)
            tls.sendall(
                f"GET {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n".encode(
                    "ascii"
                )
            )
            status = tls.recv(4096).split(b"\r\n", 1)[0].decode("iso-8859-1")
        print(f"{label}: {status} ({time.monotonic() - started:.2f}s)")
        return status.startswith("HTTP/")
    finally:
        raw.close()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Verify SOCKS and HTTP bridge layers.")
    parser.add_argument("--socks-host", default="127.0.0.1")
    parser.add_argument("--socks-port", type=int, default=10809)
    parser.add_argument("--http-host", default="127.0.0.1")
    parser.add_argument("--http-port", type=int, default=17898)
    parser.add_argument("--target-host", default="chatgpt.com")
    parser.add_argument("--target-port", type=int, default=443)
    parser.add_argument("--target-path", default="/")
    parser.add_argument("--timeout", type=float, default=15.0)
    args = parser.parse_args(argv)

    failures = 0
    try:
        greeting = socket.create_connection(
            (args.socks_host, args.socks_port), timeout=args.timeout
        )
        greeting.sendall(b"\x05\x01\x00")
        reply = recv_exact(greeting, 2)
        greeting.close()
        print(f"SOCKS greeting: {reply!r}")
        failures += reply != b"\x05\x00"
    except Exception as exc:
        print(f"SOCKS greeting: ERROR {type(exc).__name__}: {exc}")
        failures += 1

    probes = (
        (
            "SOCKS HTTPS",
            lambda: connect_via_socks5(
                (args.socks_host, args.socks_port),
                (args.target_host, args.target_port),
                args.timeout,
            ),
        ),
        (
            "HTTP proxy HTTPS",
            lambda: _http_connect(
                (args.http_host, args.http_port),
                args.target_host,
                args.target_port,
                args.timeout,
            ),
        ),
    )
    for label, factory in probes:
        try:
            if not _https_status(
                label, factory, args.target_host, args.target_path, args.timeout
            ):
                failures += 1
        except Exception as exc:
            print(f"{label}: ERROR {type(exc).__name__}: {exc}")
            failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
