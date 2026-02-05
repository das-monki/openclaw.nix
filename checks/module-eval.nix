# Check that the Home Manager module evaluates correctly
{
  pkgs,
  home-manager,
  openclawModule,
}:

let
  # Test 1: Basic module evaluation
  basicEval = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      openclawModule
      {
        home.username = "testuser";
        home.homeDirectory = "/home/testuser";
        home.stateVersion = "24.05";

        services.openclaw = {
          enable = true;
          settings = {
            gateway.mode = "local";
          };
          skillPackages = [ pkgs.jq ];
          skills = { };
        };
      }
    ];
  };

  # Test 2: With skills
  withSkillsEval = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      openclawModule
      {
        home.username = "testuser";
        home.homeDirectory = "/home/testuser";
        home.stateVersion = "24.05";

        services.openclaw = {
          enable = true;
          settings.gateway.mode = "local";
          skillPackages = [
            pkgs.jq
            pkgs.curl
          ];
          skills = {
            test-skill = pkgs.writeText "test-skill.md" ''
              # Test Skill
              This is a test skill.
            '';
          };
        };
      }
    ];
  };

  # Test 3: With secretFiles
  withSecretsEval = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      openclawModule
      {
        home.username = "testuser";
        home.homeDirectory = "/home/testuser";
        home.stateVersion = "24.05";

        services.openclaw = {
          enable = true;
          settings.gateway.mode = "local";
          secretFiles = {
            ANTHROPIC_API_KEY = "/run/secrets/anthropic";
            TELEGRAM_BOT_TOKEN = "/run/secrets/telegram";
          };
        };
      }
    ];
  };

  # Extract test results
  basicConfig = basicEval.config.home.file.".openclaw/openclaw.json".source or null;
  skillFile =
    withSkillsEval.config.home.file.".openclaw/workspace/skills/test-skill.md".source or null;
  wrapperPackage = builtins.head (withSecretsEval.config.home.packages or [ ]);

  # Check systemd service is defined (Linux only)
  systemdService =
    if pkgs.stdenv.isLinux then
      basicEval.config.systemd.user.services.openclaw-gateway or null
    else
      "skipped-on-darwin";

  # Check launchd agent is defined (Darwin only)
  launchdAgent =
    if pkgs.stdenv.isDarwin then
      basicEval.config.launchd.agents.openclaw-gateway or null
    else
      "skipped-on-linux";

in

pkgs.runCommand "openclaw-module-eval-check" { } ''
  echo "========================================"
  echo "Home Manager Module Evaluation Tests"
  echo "========================================"
  echo ""

  # Test 1: Basic evaluation
  echo "Test 1: Basic module evaluation..."
  ${
    if basicConfig != null then
      ''
        echo "  PASS: Config file generated"
        echo "  Config: ${basicConfig}"
      ''
    else
      ''
        echo "  FAIL: Config file not generated"
        exit 1
      ''
  }
  echo ""

  # Test 2: Skills
  echo "Test 2: Skills integration..."
  ${
    if skillFile != null then
      ''
        echo "  PASS: Skill file symlinked"
        echo "  Skill: ${skillFile}"
      ''
    else
      ''
        echo "  FAIL: Skill file not found"
        exit 1
      ''
  }
  echo ""

  # Test 3: Wrapper with secrets
  echo "Test 3: Gateway wrapper with secrets..."
  ${
    if wrapperPackage != null then
      ''
        echo "  PASS: Wrapper package created"
      ''
    else
      ''
        echo "  FAIL: Wrapper package not found"
        exit 1
      ''
  }
  echo ""

  # Test 4: Service definition
  echo "Test 4: Service definition..."
  ${
    if systemdService != null then
      ''
        echo "  PASS: systemd service defined (or skipped on Darwin)"
      ''
    else
      ''
        echo "  FAIL: systemd service not defined"
        exit 1
      ''
  }
  ${
    if launchdAgent != null then
      ''
        echo "  PASS: launchd agent defined (or skipped on Linux)"
      ''
    else
      ''
        echo "  FAIL: launchd agent not defined"
        exit 1
      ''
  }
  echo ""

  echo "========================================"
  echo "All Home Manager tests passed!"
  echo "========================================"

  mkdir -p $out
  echo "passed" > $out/result
''
