# Validate a minimal config through openclaw's Zod schema
{
  lib,
  runCommand,
  nodejs_22,
  configSchema,
}:

let
  # Minimal test config
  testConfig = builtins.toJSON {
    gateway = {
      mode = "local";
    };
  };

  testConfigFile = builtins.toFile "test-config.json" testConfig;
in

runCommand "openclaw-config-schema-check"
  {
    nativeBuildInputs = [ nodejs_22 ];
  }
  ''
    echo "Testing openclaw Zod schema validation..."
    echo "Validator: ${configSchema}/bin/validate-openclaw-config"
    echo "Config: ${testConfigFile}"
    echo ""
    echo "Input config:"
    cat ${testConfigFile}
    echo ""

    echo "Parsing through Zod schema (applies defaults)..."
    ${configSchema}/bin/validate-openclaw-config ${testConfigFile} > validated.json

    echo ""
    echo "Validation passed! Config with defaults applied:"
    head -30 validated.json
    echo "..."
    echo ""

    mkdir -p $out
    cp validated.json $out/config-with-defaults.json
    echo "passed" > $out/result
  ''
