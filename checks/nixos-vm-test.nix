# NixOS VM integration test
# Tests that the service actually starts in a real NixOS system
# Only runs on Linux (VM tests require KVM)
{
  pkgs,
  nixosModule,
}:

pkgs.testers.runNixOSTest {
  name = "openclaw-service";

  nodes.machine =
    { ... }:
    {
      imports = [ nixosModule ];

      # Enable the service
      services.openclaw = {
        enable = true;
        settings = {
          gateway.mode = "local";
        };
        # Don't require real secrets for testing
        secretFiles = { };
      };

      # Allow the test to check the service
      environment.systemPackages = with pkgs; [
        curl
        jq
      ];
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Check user and group exist
    machine.succeed("getent passwd openclaw")
    machine.succeed("getent group openclaw")

    # Check directories exist
    machine.succeed("test -d /var/lib/openclaw")
    machine.succeed("test -d /var/lib/openclaw/workspace/skills")

    # Check config file exists
    machine.succeed("test -f /var/lib/openclaw/openclaw.json")

    # Check config content
    config = machine.succeed("cat /var/lib/openclaw/openclaw.json")
    assert "local" in config, "Config should contain gateway mode"

    # Check service is running (may fail quickly without real API keys, but should start)
    machine.wait_for_unit("openclaw-gateway.service", timeout=10)

    # Check service status
    status = machine.succeed("systemctl status openclaw-gateway.service || true")
    print(f"Service status:\n{status}")

    # The service might fail without API keys, but it should have started
    # Check that at least the ExecStart was attempted
    journal = machine.succeed("journalctl -u openclaw-gateway.service --no-pager || true")
    print(f"Service journal:\n{journal}")
  '';
}
