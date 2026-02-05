# Check that the Home Manager module evaluates correctly
{
  pkgs,
  home-manager,
  openclawModule,
}:

let
  # Evaluate the module with a minimal test configuration
  evaluated = home-manager.lib.homeManagerConfiguration {
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

  # Extract the generated config
  configText = evaluated.config.home.file.".openclaw/openclaw.json".text or null;

in

pkgs.runCommand "openclaw-module-eval-check" { } ''
  echo "Checking Home Manager module evaluation..."

  ${
    if configText != null then
      ''
        echo "Module evaluated successfully!"
        echo "Generated config:"
        echo '${configText}'
      ''
    else
      ''
        echo "ERROR: Config file not generated"
        exit 1
      ''
  }

  mkdir -p $out
  echo "passed" > $out/result
''
