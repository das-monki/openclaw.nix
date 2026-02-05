# openclaw.nix

Declarative [Nix](https://nixos.org/) module for [Openclaw](https://openclaw.ai) - your personal AI assistant.

## Features

- **Home Manager module** - user-level service with systemd (Linux) or launchd (macOS)
- **NixOS module** - system-level service with dedicated user
- **Secrets integration** - works with [agenix](https://github.com/ryantm/agenix), [sops-nix](https://github.com/Mic92/sops-nix), or plain files
- **Skills support** - bundle CLI tools with markdown skill docs
- **Config validation** - optional JSON schema validation at build time

## Quick Start

Add to your flake inputs:

```nix
{
  inputs = {
    openclaw-nix = {
      url = "github:YOURUSERNAME/openclaw.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

### Home Manager (recommended)

```nix
{ config, pkgs, ... }:

{
  imports = [ inputs.openclaw-nix.homeManagerModules.default ];

  services.openclaw = {
    enable = true;

    settings = {
      gateway.mode = "local";
      channels.telegram.enable = true;
    };

    secretFiles = {
      ANTHROPIC_API_KEY = config.age.secrets.anthropic.path;
      TELEGRAM_BOT_TOKEN = config.age.secrets.telegram.path;
    };

    skillPackages = with pkgs; [ jq curl ripgrep ];

    skills = {
      weather = ./skills/weather.md;
    };
  };
}
```

### NixOS System Service

For headless servers where you want the service to start at boot:

```nix
{ config, ... }:

{
  imports = [ inputs.openclaw-nix.nixosModules.default ];

  services.openclaw = {
    enable = true;
    user = "openclaw";  # dedicated system user
    stateDir = "/var/lib/openclaw";

    settings = {
      gateway.mode = "local";
    };

    secretFiles = {
      ANTHROPIC_API_KEY = config.age.secrets.anthropic.path;
    };
  };
}
```

## Options

### Home Manager

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the openclaw service |
| `package` | package | from llm-agents | Openclaw package to use |
| `settings` | attrs | `{}` | Configuration (converted to JSON) |
| `secretFiles` | attrsOf str | `{}` | Env var → secret file path |
| `skillPackages` | listOf package | `[]` | CLI tools for skills |
| `skills` | attrsOf path | `{}` | Skill name → markdown path |
| `stateDir` | str | `~/.openclaw` | State directory |
| `gatewayPort` | port | `18789` | Gateway port |

### NixOS

Same as above, plus:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `user` | str | `"openclaw"` | System user |
| `group` | str | `"openclaw"` | System group |
| `stateDir` | str | `/var/lib/openclaw` | State directory |

## Skills

Skills are markdown files that teach the AI how to use CLI tools. Place them in your config and reference them:

```nix
services.openclaw = {
  skillPackages = [ pkgs.curl pkgs.jq ];
  skills = {
    weather = ./skills/weather.md;
  };
};
```

Example skill (`skills/weather.md`):

```markdown
# Weather Skill

Get current weather using wttr.in.

## Usage

```bash
curl -s "wttr.in/${LOCATION}?format=3"
```

## Examples

- Current weather: `curl -s "wttr.in/London?format=3"`
- Detailed forecast: `curl -s "wttr.in/London"`
```

## Secrets Management

This module expects secret file paths, not the secrets themselves. This works with:

### agenix

```nix
age.secrets.anthropic.file = ./secrets/anthropic.age;

services.openclaw.secretFiles = {
  ANTHROPIC_API_KEY = config.age.secrets.anthropic.path;
};
```

### sops-nix

```nix
sops.secrets.anthropic = { };

services.openclaw.secretFiles = {
  ANTHROPIC_API_KEY = config.sops.secrets.anthropic.path;
};
```

### Plain files

```nix
services.openclaw.secretFiles = {
  ANTHROPIC_API_KEY = "/run/keys/anthropic";
};
```

## Service Management

### Home Manager (systemd)

```bash
# Status
systemctl --user status openclaw-gateway

# Logs
journalctl --user -u openclaw-gateway -f

# Restart
systemctl --user restart openclaw-gateway
```

### Home Manager (launchd/macOS)

```bash
# Status
launchctl print gui/$UID/com.openclaw.gateway

# Logs
tail -f /tmp/openclaw-gateway.log

# Restart
launchctl kickstart -k gui/$UID/com.openclaw.gateway
```

### NixOS System Service

```bash
# Status
systemctl status openclaw-gateway

# Logs
journalctl -u openclaw-gateway -f

# Restart
systemctl restart openclaw-gateway
```

## Development

```bash
# Check flake
nix flake check

# Build package
nix build .#openclaw

# Test module evaluation
nix build .#checks.x86_64-linux.module-eval
```

## License

MIT
