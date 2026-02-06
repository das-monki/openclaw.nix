# Test validation with partial channel configs through Zod
# This tests that Zod correctly applies defaults to nested channel configurations
{
  lib,
  runCommand,
  nodejs_22,
  configSchema,
}:

let
  # Realistic partial channel config - like users would actually write
  # Zod should apply defaults (dmPolicy, streamMode, debounceMs, etc.)
  testConfig = builtins.toJSON {
    gateway.mode = "local";

    # Partial telegram config - Zod should add dmPolicy, streamMode, etc.
    channels.telegram = {
      botToken = "test-token";
      allowFrom = [ 123456789 ];
    };

    # Partial whatsapp config - Zod should add debounceMs, dmPolicy, etc.
    channels.whatsapp.accounts.main = {
      enabled = true;
      authDir = "/tmp/whatsapp-auth";
      allowFrom = [ "+1234567890" ];
    };
  };

  testConfigFile = builtins.toFile "test-config-channels.json" testConfig;
in

runCommand "openclaw-config-schema-channels-check"
  {
    nativeBuildInputs = [ nodejs_22 ];
  }
  ''
    echo "Testing channel config validation through Zod..."
    echo "This verifies that Zod applies defaults to nested channel configs."
    echo ""
    echo "Input config (partial channel configs):"
    cat ${testConfigFile}
    echo ""

    echo "Parsing through Zod schema..."
    ${configSchema}/bin/validate-openclaw-config ${testConfigFile} > validated.json

    echo ""
    echo "Validation passed! Checking that defaults were applied..."

    # Verify telegram defaults were applied
    if grep -q '"dmPolicy"' validated.json; then
      echo "✓ telegram.dmPolicy default applied"
    else
      echo "✗ telegram.dmPolicy missing!"
      exit 1
    fi

    if grep -q '"streamMode"' validated.json; then
      echo "✓ telegram.streamMode default applied"
    else
      echo "✗ telegram.streamMode missing!"
      exit 1
    fi

    # Verify whatsapp defaults were applied
    if grep -q '"debounceMs"' validated.json; then
      echo "✓ whatsapp.debounceMs default applied"
    else
      echo "✗ whatsapp.debounceMs missing!"
      exit 1
    fi

    if grep -q '"mediaMaxMb"' validated.json; then
      echo "✓ whatsapp.mediaMaxMb default applied"
    else
      echo "✗ whatsapp.mediaMaxMb missing!"
      exit 1
    fi

    echo ""
    echo "All channel defaults correctly applied!"
    echo ""
    echo "Output config excerpt:"
    head -80 validated.json
    echo "..."

    mkdir -p $out
    cp validated.json $out/config-with-defaults.json
    echo "passed" > $out/result
  ''
