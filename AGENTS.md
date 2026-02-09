# Agent Instructions for openclaw.nix

This file contains instructions for AI agents working on this repository.

## Repository Structure

- `flake.nix` - Main flake with packages, modules, and checks
- `packages/` - Nix package definitions
  - `config-schema.nix` - Extracts Zod validator from openclaw source
- `modules/` - NixOS and Home Manager modules
  - `home-manager/default.nix` - User-level service module
  - `nixos/default.nix` - System-level service module
- `checks/` - Flake checks for validation
- `lib/` - Shared library functions

## Key Maintenance Tasks

### Updating llm-agents Input

When the `llm-agents` flake input is updated (provides the openclaw package), the pnpm dependency hash in `packages/config-schema.nix` must also be updated:

1. Set `hash = "";` in `packages/config-schema.nix`
2. Run `nix build .#openclaw-config-schema` - it will fail with the correct hash
3. Update the hash with the value from the error message
4. Run `nix flake check` to verify

### Config Validation

The config-schema package bundles a Zod validator using esbuild. This validator:
- Parses user configs through openclaw's actual Zod schema
- Applies `.default()` at all nested levels
- Outputs config with defaults applied
- Uses absolute node path in shebang (not `/usr/bin/env` - doesn't work in Nix sandbox)

### Before Committing

Always run:
```bash
nix fmt .
nix flake check
```

## Module Architecture

Both modules (Home Manager and NixOS) follow the same pattern:
1. User provides partial `settings` (Nix attrs)
2. Settings converted to JSON (`rawConfigFile`)
3. If `validateConfig = true`:
   - Parse through Zod validator (applies defaults)
   - Output `validatedConfigFile` with defaults applied
4. Config file deployed to state directory
5. Wrapper script sets up PATH and loads secrets from files

## Skills and Plugins

There are three ways to add skills:

### `plugins` (Recommended)
Bundles a skill markdown file with its required CLI tools:
```nix
plugins = {
  weather = {
    skill = ./skills/weather.md;
    packages = [ pkgs.curl pkgs.jq ];
    secrets = [ "WEATHER_API_KEY" ];  # optional validation
  };
};
```
- Plugin packages are added to PATH
- Plugin skills are symlinked to workspace
- Required secrets are validated at service start

### `skills`
Simple skills without CLI dependencies:
```nix
skills = {
  notes = ./skills/notes.md;
};
```

### `skillPackages`
Global CLI tools available to all skills:
```nix
skillPackages = [ pkgs.ripgrep pkgs.fd ];
```

## Key Module Variables

- `allPackages` = `skillPackages` ++ packages from all plugins
- `allSkills` = `skills` // skills from all plugins
- `pluginType` = submodule with `skill`, `packages`, `secrets` options
