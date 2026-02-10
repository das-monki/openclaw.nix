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
  pluginPackages = lib.flatten (lib.mapAttrsToList (_: p: p.packages or [ ]) cfg.plugins);
  allPackages = cfg.skillPackages ++ pluginPackages;

  # Collect all skills from plugins + skills
  pluginSkills = lib.mapAttrs' (name: p: {
    name = name;
    value = p.skill;
  }) cfg.plugins;
  allSkills = cfg.skills // pluginSkills;

  # Collect all required secrets from plugins
  requiredSecrets = lib.unique (
    lib.flatten (lib.mapAttrsToList (_: p: p.secrets or [ ]) cfg.plugins)
  );

  # Build the PATH for tool execution (same as gateway wrapper)
  toolExecPath = lib.makeBinPath allPackages;

  # Inject workspace and tool exec path into settings
  settingsWithDefaults = lib.recursiveUpdate cfg.settings {
    agents.defaults.workspace = cfg.workspaceDir;
    # Prepend plugin package paths to tool execution PATH
    tools.exec.pathPrepend = [ toolExecPath ] ++ (cfg.settings.tools.exec.pathPrepend or [ ]);
  };

  configJson = builtins.toJSON settingsWithDefaults;
  rawConfigFile = pkgs.writeText "openclaw.json" configJson;

  # Build config schema for validation
  configSchema = pkgs.callPackage configSchemaPackage {
    openclaw = cfg.package;
  };

  # Validated config file (parses through Zod which applies all defaults)
  validatedConfigFile = pkgs.runCommand "openclaw-validated-config.json" { } ''
    echo "Validating config through openclaw's Zod schema..."
    echo "This applies runtime defaults to all configured paths."
    echo ""

    # Parse through Zod - applies defaults and validates
    ${configSchema}/bin/validate-openclaw-config ${rawConfigFile} > $out

    echo "Validation passed!"
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
      secrets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Environment variables required by this skill (for validation)";
      };
    };
  };

  gatewayWrapper = pkgs.writeShellScriptBin "openclaw-gateway-wrapper" ''
    set -euo pipefail

    # Add skill/plugin packages to PATH
    ${lib.optionalString (allPackages != [ ]) ''
      export PATH="${lib.makeBinPath allPackages}:$PATH"
    ''}

    # Load secrets from files
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: path: ''
        if [ -f "${path}" ]; then
          export ${name}="$(cat "${path}")"
        fi
      '') cfg.secretFiles
    )}

    # Runtime check for required secrets from plugins
    ${lib.optionalString (requiredSecrets != [ ]) ''
      missing=""
      ${lib.concatStringsSep "\n" (
        map (secret: ''
          if [ -z "''${${secret}:-}" ]; then
            missing="$missing ${secret}"
          fi
        '') requiredSecrets
      )}
      if [ -n "$missing" ]; then
        echo "Warning: Missing required secrets for plugins:$missing" >&2
      fi
    ''}

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
        Validate config through openclaw's Zod schema at build time.
        When enabled, the user config is parsed through the exact same Zod
        schema that openclaw uses at runtime. This applies all defaults to
        configured paths and validates the result. Invalid configs will fail
        the build. The deployed config file includes all defaults applied.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Build-time validation: check that required secrets are wired
    assertions = map (secret: {
      assertion = cfg.secretFiles ? ${secret};
      message =
        "openclaw: Plugin requires secret '${secret}' in services.openclaw.secretFiles. "
        + "Add it or set the plugin's secrets = [] if not needed.";
    }) requiredSecrets;

    users.users.${cfg.user} = lib.mkIf (cfg.user == "openclaw") {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
      createHome = true;
      description = "Openclaw service user";
      # Add skill/plugin packages to user profile so they're in PATH for tool execution
      packages = allPackages;
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
