# Extract JSON schema from openclaw source for config validation
{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  pnpm,
  cacert,
  openclaw,
}:

stdenv.mkDerivation {
  pname = "openclaw-config-schema";
  version = openclaw.version;

  # Fetch source matching the package version
  src = fetchFromGitHub {
    owner = "openclaw";
    repo = "openclaw";
    rev = "v${openclaw.version}";
    hash = openclaw.src.outputHash;
  };

  nativeBuildInputs = [
    nodejs_22
    pnpm
    cacert
  ];

  # Skip configure phase
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    export HOME=$TMPDIR
    export npm_config_cache=$TMPDIR/.npm

    # Install dependencies
    pnpm install --frozen-lockfile --ignore-scripts

    # Extract schema using tsx
    pnpm exec tsx -e "
      import { ClawdbotSchema } from './src/config/zod-schema.ts';
      const schema = ClawdbotSchema.toJSONSchema({
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
