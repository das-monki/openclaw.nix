# Validate a test config by merging with upstream defaults and checking against schema
{
  lib,
  runCommand,
  jq,
  check-jsonschema,
  configSchema,
}:

let
  # Minimal test config - will be merged with defaults before validation
  testConfig = builtins.toJSON {
    gateway = {
      mode = "local";
    };
  };

  testConfigFile = builtins.toFile "test-config.json" testConfig;
in

runCommand "openclaw-config-schema-check"
  {
    nativeBuildInputs = [
      jq
      check-jsonschema
    ];
  }
  ''
    echo "Testing openclaw config schema validation..."
    echo "Schema: ${configSchema}/config-schema.json"
    echo "Defaults: ${configSchema}/config-defaults.json"
    echo "User config: ${testConfigFile}"
    echo ""
    echo "User config contents:"
    cat ${testConfigFile}
    echo ""

    echo "Defaults excerpt (first 30 lines):"
    head -30 ${configSchema}/config-defaults.json
    echo "..."
    echo ""

    echo "Merging user config with defaults..."
    jq -s '.[0] * .[1]' \
      ${configSchema}/config-defaults.json \
      ${testConfigFile} \
      > merged-config.json

    echo "Merged config excerpt (first 50 lines):"
    head -50 merged-config.json
    echo "..."
    echo ""

    echo "Validating merged config against schema..."
    check-jsonschema \
      --schemafile ${configSchema}/config-schema.json \
      merged-config.json

    echo ""
    echo "Validation passed!"
    mkdir -p $out
    cp merged-config.json $out/config-with-defaults.json
    echo "passed" > $out/result
  ''
