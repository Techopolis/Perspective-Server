# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | ✅ Yes    |

## Reporting a Vulnerability

If you discover a security vulnerability in Perspective Intelligence, please **do not** open a public GitHub issue.

Instead, report it by emailing the maintainers or opening a [GitHub Security Advisory](https://github.com/Techopolis-Online/Perspective-Intelligence/security/advisories/new) (private disclosure).

Please include:

- A description of the vulnerability
- Steps to reproduce the issue
- The potential impact
- Any suggested mitigations (optional)

We will acknowledge your report within 48 hours and aim to release a fix within 14 days for critical issues.

## Security Considerations

Perspective Intelligence runs a local HTTP server bound to `localhost` only. The server:

- **Does not authenticate requests** — any process on the same machine can call the API. Do not expose the port to external networks.
- **Does not transmit data off-device** — all inference runs on-device via Apple's Foundation Models framework.
- **Requires App Sandbox entitlements** — the app is sandboxed with only `com.apple.security.network.client` and `com.apple.security.network.server`.

If you are running the server in a shared or multi-user environment, ensure port `11434` (or your configured port) is firewalled from other users.
