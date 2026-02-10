# Browser Tool Troubleshooting (Linux)

This document covers debugging the "Port is already in use" and "Can't reach browser control service" errors on Linux servers.

## The Problem

OpenClaw's browser tool frequently fails on Linux with errors like:

```
Can't reach the OpenClaw browser control service. Start (or restart) the OpenClaw gateway and try again.
(Error: PortInUseError: Port 18801 is already in use.)
```

Or timeout errors where the port is bound but Chrome isn't responding:

```
Can't reach the OpenClaw browser control service (timed out after 20000ms).
```

### Root Cause

Based on upstream issues (#7665, #10299, #10994):

1. **Old Chrome processes aren't properly cleaned up** - When Chrome crashes or times out, OpenClaw doesn't always kill the old process before spawning a new one
2. **Port stays bound** - The old Chrome holds onto the CDP port (18800-18899 range)
3. **New spawn fails** - Next browser action tries to use the same port → `PortInUseError`
4. **GPU subprocess blocks CDP** - In headless mode, Chrome spawns a GPU subprocess using SwiftShader software rendering. This subprocess can spin at high CPU (70%+) and block the main process from responding to CDP requests, causing timeouts even though the port is bound

### Port Allocation Scheme

OpenClaw derives browser ports from the gateway port (default 18789):

| Service | Default Port | Derivation |
|---------|-------------|------------|
| Gateway | 18789 | configured |
| Browser control | 18791 | gateway + 2 |
| Extension relay | 18792 | gateway + 3 |
| CDP ports | 18800-18899 | profile-specific |

## Debugging Commands

### 1. Check Browser Status

```bash
openclaw browser status --json
```

Expected healthy output shows `running: true` and an active profile.

### 2. Check What's Using the Port

```bash
# Find process on specific port
ss -tlnp | grep 18801
# or
lsof -i :18801

# Check all browser-related ports
ss -tlnp | grep -E '188[0-9]{2}'
```

### 3. Check if CDP is Responding

If the port is bound but browser tools are timing out, Chrome may be stuck:

```bash
# Quick CDP health check (should return JSON within 1-2s)
curl -v --max-time 5 http://127.0.0.1:18801/json/version

# If curl connects but hangs, Chrome is stuck (GPU subprocess issue)
# If curl fails to connect, port may be bound by zombie process
```

### 4. Check Chrome Subprocess CPU Usage

```bash
# Find the GPU process - if it's at high CPU, it's blocking CDP
ps aux | grep chromium | grep gpu-process

# Example output showing stuck GPU process at 76% CPU:
# openclaw 2478119 76.0 2.2 ... chromium --type=gpu-process ...
```

### 5. Find Orphaned Chrome Processes

```bash
# List all Chrome/Chromium processes
ps aux | grep -E 'chrom|chromium' | grep -v grep

# Find processes with openclaw user-data-dir
ps aux | grep 'user-data-dir=.*openclaw' | grep -v grep

# Find processes with remote-debugging-port
ps aux | grep 'remote-debugging-port' | grep -v grep
```

### 6. Check Gateway Logs

```bash
# Follow logs
openclaw logs --follow

# Or via journalctl for systemd service
journalctl --user -u openclaw-gateway -f
```

### 7. Full Diagnostic

```bash
openclaw doctor
openclaw status
openclaw gateway status
```

## Quick Fixes

### Kill Orphaned Chrome Processes

```bash
# Kill by user-data-dir pattern (kills main process + all subprocesses)
pkill -9 -f 'user-data-dir=.*openclaw'

# Kill by debugging port
pkill -f 'remote-debugging-port=1880'

# Nuclear option - kill all Chrome (careful if you have other Chrome windows)
pkill -9 chrome
pkill -9 chromium
```

**Note:** Use `-9` (SIGKILL) to ensure stuck GPU processes are terminated. A regular SIGTERM may not work if Chrome is unresponsive.

### Reset Browser Profile

```bash
openclaw browser reset-profile --profile openclaw
```

### Restart Gateway

```bash
# Via openclaw CLI
openclaw gateway restart

# Via systemd
systemctl --user restart openclaw-gateway
```

## Tuning Chrome for Headless Servers

The GPU subprocess issue can be mitigated with additional Chrome flags. Since OpenClaw doesn't currently support custom Chrome args directly, wrap the Chromium binary:

### NixOS Wrapper Approach

In your NixOS configuration, create a wrapped Chromium with the necessary flags:

```nix
let
  # Wrap Chromium with flags to prevent GPU subprocess from spinning
  chromiumHeadless = pkgs.writeShellScriptBin "chromium" ''
    exec ${pkgs.chromium}/bin/chromium \
      --disable-software-rasterizer \
      "$@"
  '';
in
{
  services.openclaw.settings.browser = {
    executablePath = "${chromiumHeadless}/bin/chromium";
    # ... rest of browser config
  };
}
```

**Key flag:**
- `--disable-software-rasterizer` - Disables SwiftShader CPU-based rendering

This prevents the GPU subprocess from spinning at high CPU (70%+) on small ARM servers like Hetzner CAX11.

**Note:** Avoid `--in-process-gpu` on ARM as it can cause Chrome to crash.

## Workaround: Persistent Chrome Service

PR #12094 proposes running Chrome as a persistent systemd service instead of letting OpenClaw spawn it on demand. This avoids port conflicts entirely.

### Setup

1. **Create Xvfb service** (`~/.config/systemd/user/openclaw-xvfb.service`):

```ini
[Unit]
Description=OpenClaw virtual display :100 for browser automation
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/Xvfb :100 -screen 0 1920x1080x24 -nolisten tcp -ac
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
```

2. **Create Chrome CDP service** (`~/.config/systemd/user/openclaw-chrome.service`):

```ini
[Unit]
Description=OpenClaw Chrome CDP (port 18804)
After=network-online.target openclaw-xvfb.service
Wants=network-online.target
Requires=openclaw-xvfb.service

[Service]
Type=simple
Environment=DISPLAY=:100
Environment=HOME=%h
ExecStart=/usr/bin/google-chrome-stable \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port=18804 \
  --user-data-dir=%h/chrome-profiles/openclaw-automation \
  --no-first-run \
  --no-default-browser-check \
  --disable-background-networking \
  --disable-sync \
  --disable-extensions \
  --window-size=1365,1024
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

3. **Enable services**:

```bash
mkdir -p ~/.config/systemd/user
# Copy service files...
systemctl --user daemon-reload
systemctl --user enable --now openclaw-xvfb.service
systemctl --user enable --now openclaw-chrome.service
```

4. **Configure OpenClaw** to use the external CDP:

In `~/.openclaw/openclaw.json`:
```json
{
  "browser": {
    "profiles": {
      "external": {
        "cdpUrl": "http://127.0.0.1:18804"
      }
    },
    "defaultProfile": "external"
  }
}
```

## Upstream Issues & PRs

### Related Issues

| Issue | Title | Status |
|-------|-------|--------|
| #7665 | Browser control service timeout and CDP port start failure | Open |
| #10299 | Old Chrome processes accumulate causing CDP timeouts | Open |
| #10994 | Browser frequently becomes unreachable, CDP port stuck | Open |
| #8611 | Browser control service hangs for 15s on startup failure | Closed |

### Related PRs

| PR | Title | Status |
|----|-------|--------|
| #8614 | fix(browser): detect early chromium exit to prevent startup hang | Open |
| #9020 | fix(browser): skip port checks for remote CDP profiles | Open |
| #12094 | Docs/examples: Linux browser reliability improvements | Open |

## Architecture Notes

OpenClaw's browser control service:

1. **Control server**: HTTP service on loopback, connects to Chrome via CDP, uses Playwright for operations
2. **Profile routing**: Multiple profiles can point to local instances, remote CDP URLs, or extension relay
3. **Process lifecycle**: `launchOpenClawChrome()` spawns Chrome, waits up to 15s for CDP readiness
4. **Cleanup**: `stopOpenClawChrome()` sends SIGTERM, waits 2.5s, then SIGKILL - but this doesn't always run on crashes

The core issue is that when Chrome crashes or the gateway restarts unexpectedly, the cleanup sequence doesn't execute, leaving orphaned processes holding ports.

## NixOS-Specific Notes

When using the openclaw.nix NixOS module:

- Gateway runs as systemd service under dedicated `openclaw` user
- State directory: `/var/lib/openclaw`
- Browser profile data: `/var/lib/openclaw/browser-profiles/`
- Logs: `journalctl -u openclaw-gateway`

To debug as the openclaw user:
```bash
sudo -u openclaw openclaw browser status --json
sudo -u openclaw ps aux | grep chrome
```
