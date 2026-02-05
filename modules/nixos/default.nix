# NixOS system-level module for Openclaw
# Runs as a system service with a dedicated user
{ llm-agents }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.openclaw;

  defaultPackage = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.openclaw;

  configJson = builtins.toJSON cfg.settings;
  configFile = pkgs.writeText "openclaw.json" configJson;

  gatewayWrapper = pkgs.writeShellScriptBin "openclaw-gateway-wrapper" ''
    set -euo pipefail

    ${lib.optionalString (cfg.skillPackages != [ ]) ''
      export PATH="${lib.makeBinPath cfg.skillPackages}:$PATH"
    ''}

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: path: ''
        if [ -f "${path}" ]; then
          export ${name}="$(cat "${path}")"
        fi
      '') cfg.secretFiles
    )}

    exec "${cfg.package}/bin/openclaw" "$@"
  '';

in
{
  options.services.openclaw = {
    enable = lib.mkEnableOption "Openclaw AI assistant gateway (system service)";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "The openclaw package to use";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "openclaw";
      description = "User to run the openclaw service as";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "openclaw";
      description = "Group to run the openclaw service as";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Openclaw configuration (converted to JSON)";
    };

    secretFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variable name to secret file path mapping";
    };

    skillPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "CLI tools to make available for skills";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openclaw";
      description = "Directory for openclaw state";
    };

    gatewayPort = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "Port for the openclaw gateway";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = lib.mkIf (cfg.user == "openclaw") {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
      createHome = true;
      description = "Openclaw service user";
    };

    users.groups.${cfg.group} = lib.mkIf (cfg.group == "openclaw") { };

    systemd.services.openclaw-gateway = {
      description = "Openclaw Gateway";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${gatewayWrapper}/bin/openclaw-gateway-wrapper gateway --port ${toString cfg.gatewayPort}";
        WorkingDirectory = cfg.stateDir;
        Restart = "always";
        RestartSec = "5s";

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ cfg.stateDir ];
      };

      environment = {
        HOME = cfg.stateDir;
        OPENCLAW_CONFIG_PATH = "${cfg.stateDir}/openclaw.json";
        OPENCLAW_STATE_DIR = cfg.stateDir;
      };

      preStart = ''
        mkdir -p "${cfg.stateDir}/workspace/skills"
        ln -sf ${configFile} "${cfg.stateDir}/openclaw.json"
      '';
    };
  };
}
