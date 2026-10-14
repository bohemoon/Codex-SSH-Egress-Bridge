# Contributing

Contributions are welcome. Keep the project dependency-free at runtime and
preserve loopback-only defaults.

Before opening a pull request:

```bash
python -m unittest discover -s tests -v
python scripts/audit_public_tree.py
```

Do not submit real host aliases, user names, home directories, IP addresses,
SSH keys, tokens, device codes, or private logs. Examples must use reserved
documentation values such as `example-remote` and `example.com`.

Changes that broaden a bind address, stop processes, overwrite launchers, or
read authentication state need explicit safety checks and documentation.
