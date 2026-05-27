{ fetchFromGitHub, fetchurl, stdenv, nodejs, yarn, pnpm, cacert, lib }:

let
  mkPiExt = { name, version, owner, repo, rev, srcHash, outputHash, pkgManager ? "yarn" }:
    let
      pm = if pkgManager == "pnpm" then pnpm else yarn;
      installCmd = if pkgManager == "pnpm"
        then "pnpm install --no-frozen-lockfile --no-optional"
        else "yarn install --no-progress --non-interactive";
    in
    stdenv.mkDerivation {
      pname = name;
      inherit version;
      src = fetchFromGitHub {
        inherit owner repo rev;
        hash = srcHash;
      };
      nativeBuildInputs = [ nodejs pm cacert ];
      dontFixup = true;
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      inherit outputHash;
      buildPhase = ''
        NIX_SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt \
        HOME=$TMPDIR ${installCmd} 2>&1
      '';
      installPhase = ''
        mkdir -p "$out"
        cp -r . "$out/"
        rm -rf "$out/.npm" "$out/.cache" 2>/dev/null || true
        # Promote nested entry point to root so Pi doesn't discover it as a separate extension.
        if [ ! -f "$out/index.ts" ]; then
          if [ -f "$out/src/extension/index.ts" ]; then
            cp "$out/src/extension/index.ts" "$out/index.ts"
            sed -i 's|from "./|from "./src/extension/|g' "$out/index.ts"
            sed -i 's|from "../|from "./src/|g' "$out/index.ts"
            rm "$out/src/extension/index.ts"
          elif [ -f "$out/src/index.ts" ]; then
            cp "$out/src/index.ts" "$out/index.ts"
            sed -i 's|from "./|from "./src/|g' "$out/index.ts"
            sed -i 's|from "../|from "./|g' "$out/index.ts"
            rm "$out/src/index.ts"
          elif [ -f "$out/extensions/index.ts" ]; then
            cp "$out/extensions/index.ts" "$out/index.ts"
            sed -i 's|from "./|from "./extensions/|g' "$out/index.ts"
            sed -i 's|from "../|from "./|g' "$out/index.ts"
            rm "$out/extensions/index.ts"
            # Update package.json to point to the promoted root index.ts
            sed -i 's|"\./extensions"|"\./index.ts"|g' "$out/package.json"
          fi
        fi
      '';
    };

  mkNpmPiExt = { name, version, tarballUrl, tarballHash, outputHash }:
    stdenv.mkDerivation {
      pname = name;
      inherit version;
      src = fetchurl {
        url = tarballUrl;
        hash = tarballHash;
      };
      nativeBuildInputs = [ nodejs yarn cacert ];
      dontFixup = true;
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      inherit outputHash;
      sourceRoot = "package";
      buildPhase = ''
        NIX_SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt \
        HOME=$TMPDIR yarn install --prod --no-progress --non-interactive --ignore-engines 2>&1
      '';
      installPhase = ''
        mkdir -p "$out"
        cp -r . "$out/"
        rm -rf "$out/.npm" "$out/.cache" "$out/node_modules/.cache" 2>/dev/null || true
        # Strip generated lockfile for deterministic output
        rm -f "$out/yarn.lock" 2>/dev/null || true
        # Promote nested dist/ entry point to root so Pi doesn't discover
        # the dist/ directory as a separate extension.
        if [ ! -f "$out/index.js" ] && [ -f "$out/dist/index.js" ]; then
          cp "$out/dist/index.js" "$out/index.js"
          cp "$out/dist/index.d.ts" "$out/index.d.ts" 2>/dev/null || true
          sed -i "s|from './|from './dist/|g" "$out/index.js"
          sed -i "s|from '../|from './|g" "$out/index.js"
          sed -i 's|"\./dist/index\.js"|"./index.js"|g' "$out/package.json"
        fi
      '';
    };
in {
  pi-web-access = mkPiExt {
    name = "pi-web-access";
    version = "0.10.7";
    owner = "nicobailon";
    repo = "pi-web-access";
    rev = "v0.10.7";
    srcHash = "sha256-D9no4SLigH/t3/WfirixMbTEjcEwZwJXld8j7pwBCew=";
    outputHash = "sha256-ATfWD7DMSHGktoGrX7sEzwCvmXbgNQRrSetEHcwxRVg=";
  };

  pi-subagents = mkPiExt {
    name = "pi-subagents";
    version = "0.25.0";
    owner = "nicobailon";
    repo = "pi-subagents";
    rev = "v0.25.0";
    srcHash = "sha256-MLQ7/+xEd2xTI37rMfWaYP7I724MWN+pgXhv78OxjL8=";
    outputHash = "sha256-MzavGbgfLjqMrc7ENju+4g3Wbla5vZKxaiJzm/ZBx3o=";
  };

  pi-permission-system = mkPiExt {
    name = "pi-permission-system";
    version = "5.18.1";
    owner = "gotgenes";
    repo = "pi-permission-system";
    rev = "f1d2f619b8656f88584ff1d1c0f45936ad6b25bc";
    srcHash = "sha256-vzQMv0JgN62OmtzZltgNN2LnHu9zon6JZTBxYnRNE6w=";
    pkgManager = "pnpm";
    outputHash = "sha256-A7mI+d/Dbva5cxf4INJfIsNJh/kZxUJMtjs3f/xYX7E=";
  };

  pi-mcp-adapter = mkPiExt {
    name = "pi-mcp-adapter";
    version = "2.8.0";
    owner = "nicobailon";
    repo = "pi-mcp-adapter";
    rev = "v2.8.0";
    srcHash = "sha256-eHz/uivSIZ8HOalSCZgyCyOWodQJq5GapAqpT2ryn1k=";
    outputHash = "sha256-uMAXBjjpAjN1uDEOlUoqMKWQ8NuQqAlAJX7ehxmP+Ew=";
  };

  pi-goal = mkPiExt {
    name = "pi-goal";
    version = "0.2.0";
    owner = "zereraz";
    repo = "pi-goal";
    rev = "b7f908d813861d1743055ad6a42a400f5db17cf8";
    srcHash = "sha256-P8Agjv8xWiozzW1eTOJ1/+adIR3lZtx2GhRT9zcDJ98=";
    outputHash = "sha256-kg1Lgge59y5VVkxIRBRP9233xOfmqGW1paNLVgn01mU=";
  };

  pi-lsp = mkNpmPiExt {
    name = "pi-lsp";
    version = "0.0.33";
    tarballUrl = "https://registry.npmjs.org/@spences10/pi-lsp/-/pi-lsp-0.0.33.tgz";
    tarballHash = "sha512-gKGLlr5JSYC3xBHhzNJGgqCFU/34LsDWlN+Wiw7lJSienB9sydWxa5MkIW7ioV3ZK0aOoN7S+HueoNEYCSMZWA==";
    outputHash = "sha256-2dwCTDp9jXkg0aa2RiEL86JHPgqkwEnhsCnH3u7Pswo=";
  };

  # Add more:
  # pi-foo = mkPiExt { name = "pi-foo"; version = "1.0.0"; owner = "..."; repo = "..."; rev = "v1.0.0"; srcHash = lib.fakeHash; outputHash = lib.fakeHash; };
}
