# 007Codex Companion Distribution

Public installer and release channel for the 007Codex Companion beta.

This repository intentionally contains only distribution assets. The main
application source stays in the private development repository.

Current beta release: `v0.1.0-beta.2`

## Install

Each beta tester should receive a unique domain and Cloudflare tunnel token.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/danxizuo/007Codex-companion/main/scripts/install-companion.sh)" -- --domain u001.sci2web.top --cloudflared-token <token>
```

The installer downloads the matching release bundle, installs the Companion as
a user LaunchAgent, completes the Cloudflare forwarding config when possible,
prints both public and LAN pairing QR codes after the local service is healthy,
and then checks the public `/status` URL from the pairing domain. If the public
route is not ready yet, the LAN QR code is still usable while Cloudflare is
being fixed.

The local Companion port is selected automatically. Port `3939` is preferred,
but if it is already occupied the installer chooses the next available port and
stores it in the local config.

## Start or Restart

After installation, the iOS app can show a short Mac command for starting or
restarting the background service:

```bash
bash "$HOME/.icodex-companion/app/scripts/start-companion-service.sh"
```

This command reuses the installed config, picks an available local port, updates
the Cloudflare local target or named tunnel ingress when needed, restarts the
LaunchAgent, prints the current pairing QR codes, and verifies that Companion is
healthy before returning.

If the terminal has scrolled past the QR code, show the current pairing data
again with:

```bash
bash "$HOME/.icodex-companion/app/scripts/show-companion-pairing.sh"
```

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
