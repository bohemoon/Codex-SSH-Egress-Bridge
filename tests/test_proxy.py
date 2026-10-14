import socket
import sys
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from codex_ssh_eg.proxy import ProxyServer, _loopback_only, _parse_authority


class ProxyTests(unittest.TestCase):
    def test_parse_authority(self):
        self.assertEqual(_parse_authority("example.com:443"), ("example.com", 443))
        self.assertEqual(_parse_authority("[::1]:8080"), ("::1", 8080))

    def test_parse_authority_requires_port(self):
        with self.assertRaises(ValueError):
            _parse_authority("example.com")

    def test_loopback_guard(self):
        self.assertTrue(_loopback_only("127.0.0.1"))
        self.assertFalse(_loopback_only("0.0.0.0"))

    def test_relative_url_is_rejected_without_upstream(self):
        with ProxyServer(("127.0.0.1", 0), ("127.0.0.1", 9)) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with socket.create_connection(server.server_address, timeout=2) as client:
                    client.sendall(b"GET /relative HTTP/1.1\r\nHost: example.com\r\n\r\n")
                    response = client.recv(4096)
                self.assertTrue(response.startswith(b"HTTP/1.1 400 Bad Request"))
            finally:
                server.shutdown()
                thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
