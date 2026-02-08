# Extract JSON schema and provide Zod-based validation from openclaw source
{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  esbuild,
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
    hash = "sha256-BIdgolvS9JIJpBtttlMJ9FgP3QrGFitEIAEmigz3Z7E=";
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
    esbuild
  ];

  # Let pnpmConfigHook run during configure to set up node_modules

  buildPhase = ''
        runHook preBuild

        # Set up pnpm environment
        export HOME=$TMPDIR
        export PNPM_HOME=$TMPDIR/.pnpm

        # Extract JSON schema using tsx
        ./node_modules/.bin/tsx -e "
          import { OpenClawSchema } from './src/config/zod-schema.ts';
          const schema = OpenClawSchema.toJSONSchema({
            target: 'draft-07',
            unrepresentable: 'any'
          });
          console.log(JSON.stringify(schema, null, 2));
        " > config-schema.json

        # Create the validation script that will be bundled
        cat > validate-config.ts << 'VALIDATE_SCRIPT'
    import { readFileSync } from 'fs';
    import { OpenClawSchema } from './src/config/zod-schema.ts';

    const configPath = process.argv[2];
    if (!configPath) {
      console.error('Usage: validate-config <config.json>');
      process.exit(1);
    }

    try {
      const rawConfig = JSON.parse(readFileSync(configPath, 'utf8'));

      // Parse through Zod schema - this applies .default() at all nested levels
      const result = OpenClawSchema.safeParse(rawConfig);

      if (!result.success) {
        console.error('Config validation failed:');
        for (const issue of result.error.issues) {
          const path = issue.path.length > 0 ? issue.path.join('.') : '(root)';
          console.error('  ' + path + ': ' + issue.message);
        }
        process.exit(1);
      }

      // Output the config with all defaults applied
      console.log(JSON.stringify(result.data, null, 2));
    } catch (err) {
      console.error('Failed to parse config:', err instanceof Error ? err.message : err);
      process.exit(1);
    }
    VALIDATE_SCRIPT

        # Bundle the validation script with esbuild (self-contained, no node_modules needed)
        # First compile TypeScript, then bundle
        ./node_modules/.bin/tsx --emit validate-config.ts 2>/dev/null || true

        # Use esbuild to create a self-contained bundle
        ${esbuild}/bin/esbuild \
          --bundle \
          --platform=node \
          --target=node20 \
          --format=cjs \
          --outfile=validate-config.cjs \
          validate-config.ts

        runHook postBuild
  '';

  installPhase = ''
        runHook preInstall

        mkdir -p $out/bin

        # Install schema
        cp config-schema.json $out/

        # Install bundled validation script
        cp validate-config.cjs $out/

        # Create wrapper script with absolute node path (no /usr/bin/env in sandbox)
        cat > $out/bin/validate-openclaw-config << WRAPPER
    #!${nodejs_22}/bin/node
    require(require('path').join(__dirname, '..', 'validate-config.cjs'));
    WRAPPER
        chmod +x $out/bin/validate-openclaw-config

        runHook postInstall
  '';

  meta = {
    description = "JSON schema and Zod validator for openclaw configuration";
    homepage = "https://github.com/openclaw/openclaw";
    license = lib.licenses.mit;
  };
}
