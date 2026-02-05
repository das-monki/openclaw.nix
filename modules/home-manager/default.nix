# Home Manager module for Openclaw
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
  homeDir = config.home.homeDirectory;

  # Convert absolute path to relative (for home.file)
  toRelative =
    path: if lib.hasPrefix "${homeDir}/" path then lib.removePrefix "${homeDir}/" path else path;

  # Get openclaw package from llm-agents or user override
  defaultPackage = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.openclaw;

  # Generate JSON config from Nix
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

  # Wrapper script that sets up PATH and loads secrets
  gatewayWrapper = pkgs.writeShellScriptBin "openclaw-gateway-wrapper" ''
    set -euo pipefail

    # Add skill packages to PATH
    ${lib.optionalString (cfg.skillPackages != [ ]) ''
      export PATH="${lib.makeBinPath cfg.skillPackages}:$PATH"
    ''}

    # Load secrets from files
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
    enable = lib.mkEnableOption "Openclaw AI assistant gateway";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "llm-agents.packages.\${system}.openclaw";
      description = "The openclaw package to use";
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

    skillPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.jq pkgs.curl pkgs.ripgrep ]";
      description = "CLI tools to make available in PATH for skills";
    };

    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''
        {
          weather = ./skills/weather.md;
          calendar = ./skills/calendar.md;
        }
      '';
      description = "Skill name to markdown file path mapping";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.openclaw";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.openclaw"'';
      description = "Directory for openclaw state and config";
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
    # Ensure state directories exist
    home.activation.openclawDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${cfg.stateDir}" "${cfg.workspaceDir}" "${cfg.workspaceDir}/skills"
    '';

    # Symlink config and skills
    home.file = lib.mkMerge [
      # Config file (validated if validateConfig=true)
      { "${toRelative cfg.stateDir}/openclaw.json".source = configFile; }

      # Skills
      (lib.mapAttrs' (name: path: {
        name = "${toRelative cfg.workspaceDir}/skills/${name}.md";
        value.source = path;
      }) cfg.skills)
    ];

    # Add wrapper to PATH
    home.packages = [ gatewayWrapper ];

    # Systemd user service (Linux)
    systemd.user.services.openclaw-gateway = lib.mkIf pkgs.stdenv.isLinux {
      Unit = {
        Description = "Openclaw Gateway";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${gatewayWrapper}/bin/openclaw-gateway-wrapper gateway --port ${toString cfg.gatewayPort}";
        WorkingDirectory = cfg.stateDir;
        Restart = "always";
        RestartSec = "5s";
        Environment = [
          "HOME=${config.home.homeDirectory}"
          "OPENCLAW_CONFIG_PATH=${cfg.stateDir}/openclaw.json"
          "OPENCLAW_STATE_DIR=${cfg.stateDir}"
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };

    # Launchd agent (macOS)
    launchd.agents.openclaw-gateway = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        Label = "com.openclaw.gateway";
        ProgramArguments = [
          "${gatewayWrapper}/bin/openclaw-gateway-wrapper"
          "gateway"
          "--port"
          "${toString cfg.gatewayPort}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        WorkingDirectory = cfg.stateDir;
        StandardOutPath = "/tmp/openclaw-gateway.log";
        StandardErrorPath = "/tmp/openclaw-gateway.log";
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          OPENCLAW_CONFIG_PATH = "${cfg.stateDir}/openclaw.json";
          OPENCLAW_STATE_DIR = cfg.stateDir;
        };
      };
    };
  };
}
