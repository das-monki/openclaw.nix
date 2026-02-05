# NixOS system-level module for Openclaw
# Runs as a system service with a dedicated user
{
  llm-agents,
  configSchemaPackage,
}:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.openclaw;

  defaultPackage = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.openclaw;

  # Collect all packages from plugins + skillPackages
  pluginPackages = lib.flatten (lib.mapAttrsToList (_: p: p.packages) cfg.plugins);
  allPackages = cfg.skillPackages ++ pluginPackages;

  # Collect all skills from plugins + skills
  pluginSkills = lib.mapAttrs' (name: p: {
    name = name;
    value = p.skill;
  }) cfg.plugins;
  allSkills = cfg.skills // pluginSkills;

  configJson = builtins.toJSON cfg.settings;
  rawConfigFile = pkgs.writeText "openclaw.json" configJson;

  # Build config schema for validation
  configSchema = pkgs.callPackage configSchemaPackage {
    openclaw = cfg.package;
  };

  # Validated config file (validates at build time)
  validatedConfigFile =
    pkgs.runCommand "openclaw-validated-config.json"
      {
        nativeBuildInputs = [ pkgs.check-jsonschema ];
      }
      ''
        echo "Validating openclaw config against upstream schema..."
        check-jsonschema --schemafile ${configSchema}/config-schema.json ${rawConfigFile}
        echo "Validation passed!"
        cp ${rawConfigFile} $out
      '';

  # Use validated or raw config based on setting
  configFile = if cfg.validateConfig then validatedConfigFile else rawConfigFile;

  # Script to symlink skills (from both skills and plugins)
  skillsSetup = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: path: ''
      ln -sf ${path} "${cfg.workspaceDir}/skills/${name}.md"
    '') allSkills
  );

  # Plugin submodule type
  pluginType = lib.types.submodule {
    options = {
      skill = lib.mkOption {
        type = lib.types.path;
        description = "Path to the skill markdown file";
      };
      packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "CLI tools required by this skill";
      };
    };
  };

  gatewayWrapper = pkgs.writeShellScriptBin "openclaw-gateway-wrapper" ''
    set -euo pipefail

    # Add skill/plugin packages to PATH
    ${lib.optionalString (allPackages != [ ]) ''
      export PATH="${lib.makeBinPath allPackages}:$PATH"
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
      defaultText = lib.literalExpression "llm-agents.packages.\${system}.openclaw";
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
      type = lib.types.submodule {
        freeformType = lib.types.attrsOf lib.types.anything;
        options = {
          gateway = lib.mkOption {
            type = lib.types.submodule {
              freeformType = lib.types.attrsOf lib.types.anything;
              options.mode = lib.mkOption {
                type = lib.types.enum [
                  "local"
                  "remote"
                ];
                default = "local";
                description = "Gateway mode";
              };
            };
            default = { };
            description = "Gateway configuration";
          };
        };
      };
      default = { };
      description = "Openclaw configuration (converted to JSON)";
    };

    secretFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''
        {
          ANTHROPIC_API_KEY = config.age.secrets.anthropic.path;
          TELEGRAM_BOT_TOKEN = config.age.secrets.telegram.path;
        }
      '';
      description = ''
        Mapping of environment variable names to secret file paths.
        At runtime, the contents of each file are read and exported.
        Compatible with agenix, sops-nix, or any secrets manager.
      '';
    };

    plugins = lib.mkOption {
      type = lib.types.attrsOf pluginType;
      default = { };
      example = lib.literalExpression ''
        {
          github = {
            skill = ./skills/github.md;
            packages = [ pkgs.gh ];
          };
          weather = {
            skill = ./skills/weather.md;
            packages = [ pkgs.curl pkgs.jq ];
          };
        }
      '';
      description = ''
        Plugins bundle a skill file with its required CLI tools.
        The plugin name becomes the skill name in the workspace.
      '';
    };

    skillPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.jq pkgs.curl pkgs.ripgrep ]";
      description = ''
        Global CLI tools available to all skills.
        For skill-specific tools, use plugins instead.
      '';
    };

    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''
        {
          notes = ./skills/notes.md;
        }
      '';
      description = ''
        Simple skills without CLI dependencies.
        For skills with dependencies, use plugins instead.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openclaw";
      description = "Directory for openclaw state";
    };

    workspaceDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.stateDir}/workspace";
      defaultText = lib.literalExpression ''"''${config.services.openclaw.stateDir}/workspace"'';
      description = "Directory for openclaw workspace (skills, etc.)";
    };

    gatewayPort = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "Port for the openclaw gateway";
    };

    validateConfig = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Validate config against upstream JSON schema at build time.
        When enabled, invalid configs will fail the build.
      '';
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
        # Create directories
        mkdir -p "${cfg.stateDir}" "${cfg.workspaceDir}" "${cfg.workspaceDir}/skills"

        # Symlink config (validated if validateConfig=true)
        ln -sf ${configFile} "${cfg.stateDir}/openclaw.json"

        # Symlink skills
        ${skillsSetup}
      '';
    };
  };
}
