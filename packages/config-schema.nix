# Extract JSON schema from openclaw source for config validation
{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  openclaw,
}:

let
  # Source must be defined outside stdenv.mkDerivation for fetchPnpmDeps
  src = fetchFromGitHub {
    owner = "openclaw";
    repo = "openclaw";
    rev = "v${openclaw.version}";
    hash = openclaw.src.outputHash;
  };

  # Pre-fetch pnpm dependencies (Fixed Output Derivation - has network access)
  pnpmDeps = fetchPnpmDeps {
    pname = "openclaw-config-schema-deps";
    version = openclaw.version;
    inherit src;
    pnpm = pnpm_10;
    # pnpm lockfile version (3 is latest supported)
    fetcherVersion = 3;
    hash = "sha256-uOhFo64Y0JmgY4JFjoX6z7M/Vg9mnjBa/oOPWmXz2IU=";
  };
in
stdenv.mkDerivation {
  pname = "openclaw-config-schema";
  version = openclaw.version;

  inherit src pnpmDeps;

  nativeBuildInputs = [
    nodejs_22
    pnpm_10
    pnpmConfigHook
  ];

  # Let pnpmConfigHook run during configure to set up node_modules

  buildPhase = ''
    runHook preBuild

    # Set up pnpm environment
    export HOME=$TMPDIR
    export PNPM_HOME=$TMPDIR/.pnpm

    # Extract schema using tsx (run directly from node_modules)
    ./node_modules/.bin/tsx -e "
      import { OpenClawSchema } from './src/config/zod-schema.ts';
      const schema = OpenClawSchema.toJSONSchema({
        target: 'draft-07',
        unrepresentable: 'any'
      });
      console.log(JSON.stringify(schema, null, 2));
    " > config-schema.json

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp config-schema.json $out/

    runHook postInstall
  '';

  meta = {
    description = "JSON schema for openclaw configuration";
    homepage = "https://github.com/openclaw/openclaw";
    license = lib.licenses.mit;
  };
}
