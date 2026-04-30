# 007Codex Companion Distribution

Public installer and release channel for the 007Codex Companion beta.

This repository intentionally contains only distribution assets. The main
application source stays in the private development repository.

## Install

Each beta tester should receive a unique domain and Cloudflare tunnel token.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/danxizuo/007Codex-companin/main/scripts/install-companion.sh)" -- --domain u001.sci2web.top --cloudflared-token <token>
```

The installer downloads the matching release bundle, installs the Companion as
a user LaunchAgent, starts Cloudflare Tunnel when a token is provided, and prints
the iPhone pairing QR code.

## Installed Paths

| Item | Path |
| --- | --- |
| App bundle | `~/.icodex-companion/app` |
| Product config | `~/.icodex-companion/config.json` |
| Auth token | `~/.icodex-companion/auth-token` |
| LaunchAgents | `~/Library/LaunchAgents/` |
| Logs | `~/Library/Logs/iCodexCompanion/` |

## Uninstall

```bash
bash ~/.icodex-companion/app/scripts/uninstall-companion.sh
```

Remove local config and token as well:

```bash
bash ~/.icodex-companion/app/scripts/uninstall-companion.sh --remove-data
```
