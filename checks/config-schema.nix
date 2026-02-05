# Validate a test config against the upstream schema
{
  lib,
  runCommand,
  check-jsonschema,
  configSchema,
}:

let
  # Minimal valid test config
  testConfig = builtins.toJSON {
    gateway = {
      mode = "local";
    };
  };

  testConfigFile = builtins.toFile "test-config.json" testConfig;
in

runCommand "openclaw-config-schema-check"
  {
    nativeBuildInputs = [ check-jsonschema ];
  }
  ''
    echo "Validating openclaw config against JSON schema..."
    echo "Schema: ${configSchema}/config-schema.json"
    echo "Config: ${testConfigFile}"
    echo ""
    echo "Test config contents:"
    cat ${testConfigFile}
    echo ""

    check-jsonschema \
      --schemafile ${configSchema}/config-schema.json \
      ${testConfigFile}

    echo ""
    echo "Schema validation passed!"
    mkdir -p $out
    echo "passed" > $out/result
  ''
