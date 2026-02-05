# Check that the NixOS module evaluates correctly
# Uses nixos-rebuild dry-build style evaluation
{
  pkgs,
  lib,
  nixpkgs,
  nixosModule,
}:

let
  # Evaluate as a NixOS system (without actually building)
  evaluated = lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      nixosModule
      (
        { ... }:
        {
          # Minimal bootable config
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "24.05";

          # Test the openclaw module
          services.openclaw = {
            enable = true;
            settings = {
              gateway.mode = "local";
            };
            skillPackages = [ pkgs.jq ];
            plugins = {
              github = {
                skill = pkgs.writeText "github.md" ''
                  # GitHub Skill
                  Use gh CLI.
                '';
                packages = [ pkgs.gh ];
              };
            };
            skills = {
              test-skill = pkgs.writeText "test-skill.md" ''
                # Test Skill
                This is a test.
              '';
            };
            secretFiles = {
              ANTHROPIC_API_KEY = "/run/secrets/anthropic";
            };
          };
        }
      )
    ];
  };

  cfg = evaluated.config.services.openclaw;
  systemdService = evaluated.config.systemd.services.openclaw-gateway;
  userConfig = evaluated.config.users.users.openclaw;
  groupConfig = evaluated.config.users.groups.openclaw;

in

pkgs.runCommand "openclaw-nixos-module-eval-check" { } ''
  echo "========================================"
  echo "NixOS Module Evaluation Tests"
  echo "========================================"
  echo ""

  # Test 1: Module evaluates
  echo "Test 1: Module evaluation..."
  ${
    if cfg.enable then
      ''
        echo "  PASS: Module enabled"
      ''
    else
      ''
        echo "  FAIL: Module not enabled"
        exit 1
      ''
  }
  echo ""

  # Test 2: Systemd service defined
  echo "Test 2: Systemd service..."
  ${
    if systemdService != null then
      ''
        echo "  PASS: systemd service defined"
      ''
    else
      ''
        echo "  FAIL: systemd service not defined"
        exit 1
      ''
  }
  echo ""

  # Test 3: User created
  echo "Test 3: System user..."
  ${
    if userConfig.isSystemUser then
      ''
        echo "  PASS: System user 'openclaw' defined"
      ''
    else
      ''
        echo "  FAIL: System user not properly defined"
        exit 1
      ''
  }
  echo ""

  # Test 4: Group created
  echo "Test 4: System group..."
  ${
    if groupConfig != null then
      ''
        echo "  PASS: System group 'openclaw' defined"
      ''
    else
      ''
        echo "  FAIL: System group not defined"
        exit 1
      ''
  }
  echo ""

  # Test 5: Service hardening
  echo "Test 5: Service hardening..."
  ${
    if systemdService.serviceConfig.NoNewPrivileges then
      ''
        echo "  PASS: NoNewPrivileges enabled"
      ''
    else
      ''
        echo "  FAIL: NoNewPrivileges not set"
        exit 1
      ''
  }
  echo ""

  echo "========================================"
  echo "All NixOS module tests passed!"
  echo "========================================"

  mkdir -p $out
  echo "passed" > $out/result
''
