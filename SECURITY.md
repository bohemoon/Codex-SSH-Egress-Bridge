# Security policy

## Supported versions

Security fixes are applied to the latest revision on the default branch.

## Reporting a vulnerability

Do not open a public issue containing credentials, private hostnames, internal
IP addresses, logs with tokens, or SSH configuration. Use the repository
owner's private security-reporting channel when one is available.

Include only the minimum reproduction details. Replace user names, home paths,
host aliases, IP addresses, device codes, and tokens with placeholders.

## Operational boundaries

The HTTP adapter is intentionally unauthenticated and must remain bound to a
loopback address. Anyone able to connect to that listener can use the SSH
client's network path.

Before use, verify the remote listener with a command such as:

```bash
ss -ltn | grep -E ':(10809|17898)[[:space:]]'
```

Both addresses should be loopback addresses. Do not combine this project with
SSH `GatewayPorts yes`, broad container port publication, or firewall rules
that expose either listener unless you have separately designed authentication
and access controls.

The recovery helper sends `SIGTERM` only after matching a narrow command-line,
parent-process, and missing-proxy-variable predicate. Review its output before
retrying or changing those safeguards.

This repository never needs Codex authentication files. Never attach
`~/.codex/auth.json`, environment dumps, or full app-server logs to an issue.
