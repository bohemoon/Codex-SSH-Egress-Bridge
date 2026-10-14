import socket
import sys
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from codex_ssh_eg.socks5 import (
    Socks5Error,
    _encode_destination,
    connect_via_socks5,
    recv_exact,
)


class OneShotSocksServer:
    def __init__(self):
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.address = self.listener.getsockname()
        self.destination = None
        self.thread = threading.Thread(target=self._serve, daemon=True)

    def _serve(self):
        connection, _ = self.listener.accept()
        with connection:
            self.assert_bytes(connection, b"\x05\x01\x00")
            connection.sendall(b"\x05\x00")
            prefix = recv_exact(connection, 4)
            if prefix[3] == 3:
                host = recv_exact(connection, recv_exact(connection, 1)[0]).decode("ascii")
            elif prefix[3] == 1:
                host = socket.inet_ntoa(recv_exact(connection, 4))
            else:
                raise AssertionError("unexpected address type")
            port = int.from_bytes(recv_exact(connection, 2), "big")
            self.destination = (host, port)
            connection.sendall(b"\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00")
            payload = connection.recv(4)
            if payload:
                connection.sendall(payload.upper())

    @staticmethod
    def assert_bytes(connection, expected):
        actual = recv_exact(connection, len(expected))
        if actual != expected:
            raise AssertionError(f"expected {expected!r}, got {actual!r}")

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.listener.close()
        self.thread.join(timeout=2)


class Socks5Tests(unittest.TestCase):
    def test_encode_domain(self):
        self.assertEqual(_encode_destination("example.com"), b"\x03\x0bexample.com")

    def test_encode_ipv4(self):
        self.assertEqual(_encode_destination("192.0.2.1"), b"\x01\xc0\x00\x02\x01")

    def test_rejects_invalid_port(self):
        with self.assertRaises(Socks5Error):
            connect_via_socks5(("127.0.0.1", 9), ("example.com", 0))

    def test_connect_and_relay(self):
        with OneShotSocksServer() as server:
            sock = connect_via_socks5(server.address, ("example.com", 443))
            with sock:
                sock.sendall(b"ping")
                self.assertEqual(recv_exact(sock, 4), b"PING")
        self.assertEqual(server.destination, ("example.com", 443))


if __name__ == "__main__":
    unittest.main()
