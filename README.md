# Codex SSH Egress Bridge

Run Codex on a remote Linux machine while sending its outbound HTTPS traffic
through the SSH client machine.

This project packages a small, dependency-free bridge for environments where:

- Codex runs on a Linux host reached over SSH;
- the remote host cannot reach the required HTTPS endpoints directly; and
- the SSH client has the network access you intend to use.

It combines an OpenSSH remote dynamic forward (a SOCKS5 listener on the remote
loopback interface), a tiny HTTP-to-SOCKS5 adapter, and an optional user-scoped
Codex launcher. Nothing is installed system-wide.

> [!IMPORTANT]
> This is a community workaround, not an official OpenAI networking feature.
> Use it only where proxying is permitted by your organization, network policy,
> and applicable terms. It does not bypass account, region, or service
> eligibility checks.

## Recommended: Windows GUI

Double-click `launch-gui.cmd` in the repository root. The guided interface can:

1. load aliases from the local SSH config and test a connection;
2. start or stop the reverse SOCKS tunnel;
3. copy the required project files and run the user-scoped remote installer;
4. verify transport, run read-only diagnostics, and open remote Codex.

The option to replace the default `codex` command is unchecked by default.
Local SSH configuration and logs are read only at runtime and are never added
to the repository or uploaded by the GUI.

## Architecture

```text
remote Codex
    | HTTP_PROXY=http://127.0.0.1:17898
    v
HTTP-to-SOCKS adapter (remote, loopback only)
    | SOCKS5 127.0.0.1:10809
    v
OpenSSH remote dynamic forward
    |
    v
SSH client network -> destination HTTPS service
```

The default ports are examples and can be changed. All listeners bind to
`127.0.0.1` by default.

## Requirements

On the SSH client:

- Windows PowerShell 5.1+ or PowerShell 7+
- OpenSSH client with dynamic remote forwarding support

On the remote host:

- Linux with Bash, Python 3.8+, `pgrep`, and `setsid`
- a working user-scoped Codex CLI installation
- an SSH server that permits remote TCP forwarding

For supported Codex installation and sign-in methods, follow the
[official Codex CLI documentation](https://learn.chatgpt.com/docs/codex/cli)
and [authentication documentation](https://learn.chatgpt.com/docs/auth).

## Quick start

### 1. Start the reverse SOCKS tunnel on Windows

Use an SSH alias from your own `~/.ssh/config`; do not commit that file.

```powershell
.\scripts\windows\start-reverse-socks.ps1 -SshHost example-remote
```

Keep that PowerShell window running. The script reconnects automatically and
writes its log under the current user's local application-data directory.

To use a different remote SOCKS port:

```powershell
.\scripts\windows\start-reverse-socks.ps1 `
  -SshHost example-remote `
  -RemoteSocksPort 11080
```

### 2. Install the remote user-scoped bridge

Copy or clone this repository on the remote host, then run:

```bash
./scripts/linux/install.sh
```

The installer creates `~/.local/bin/codex-ssh-eg`, a launcher that starts the
adapter when needed and then runs your existing Codex binary with proxy
environment variables.

Use it directly:

```bash
codex-ssh-eg --version
codex-ssh-eg
```

To make the bridge the default `codex` command, opt in explicitly:

```bash
./scripts/linux/install.sh --wrap-codex
```

If `~/.local/bin/codex` already exists, the installer refuses to overwrite an
unmanaged file. Remove or rename it yourself after reviewing it, then rerun the
installer. The real Codex executable is recorded at installation time to avoid
launcher recursion.

Custom ports must match on both sides:

```bash
SOCKS_PORT=11080 HTTP_PROXY_PORT=18080 ./scripts/linux/install.sh
```

### 3. Verify each network layer

On the remote host:

```bash
~/.local/bin/codex-ssh-eg-verify
~/.local/bin/codex-ssh-eg --version
```

The verifier checks the SOCKS5 greeting and an HTTPS request through both the
SOCKS listener and HTTP adapter. An HTTP authentication response still proves
that transport reached the destination; the verifier never reads Codex login
tokens.

For an end-to-end CLI check, choose a harmless prompt yourself. When launching
it through a non-interactive SSH command, close SSH stdin with `ssh -n` so the
test is not mistaken for a network hang.

## Troubleshooting `request timed out`

Run the read-only diagnostic:

```bash
~/.local/bin/codex-ssh-eg-diagnose
```

Check the layers in this order:

1. The SOCKS greeting is `b'\\x05\\x00'`.
2. The HTTP adapter is listening only on remote loopback.
3. The HTTPS probe returns promptly.
4. Every relevant Codex/app-server process has `HTTP_PROXY`, `HTTPS_PROXY`,
   `ALL_PROXY`, and `NO_PROXY` in `/proc/<pid>/environ`.
5. A stale parentless app-server is not holding the control socket while a new,
   correctly proxied launcher connects to it.

The diagnostic deliberately prints variable names and proxy loopback values,
not authentication files or token contents. It does not stop processes.

If you confirm that a parentless code-mode host owns the control socket and has
no proxy variables, use the narrowly scoped recovery helper:

```bash
~/.local/bin/codex-ssh-eg-recover-orphan
```

The helper refuses to stop a process that already has proxy variables or whose
command line does not match the expected app-server pattern.

## Uninstall

```bash
./scripts/linux/uninstall.sh
```

The uninstaller removes only files carrying this project's managed marker. It
does not remove Codex, Node.js, SSH configuration, login data, or unrelated
shell configuration.

## Security and privacy

- No usernames, home directories, host aliases, IP addresses, tokens, device
  codes, or machine identifiers are included in this repository.
- The proxy listens on loopback only. Do not expose it on a LAN or public
  interface.
- The adapter has no authentication because it is intended only for the remote
  loopback interface.
- The scripts never read or copy `~/.codex/auth.json`.
- Logs can still reveal destination hostnames and timestamps. Review local logs
  before sharing them.
- Run `python scripts/audit_public_tree.py` before publishing.

See [SECURITY.md](SECURITY.md) for reporting and operational guidance.

## Development

```bash
python -m unittest discover -s tests -v
python scripts/audit_public_tree.py
```

The runtime uses only the Python standard library.

## License

MIT. See [LICENSE](LICENSE).

Codex and OpenAI are trademarks of their respective owners. This project is
independent and is not endorsed by OpenAI.
