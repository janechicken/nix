{ fetchFromGitHub, stdenv, nodejs, yarn, pnpm, cacert, lib }:

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
          fi
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

  # Add more:
  # pi-foo = mkPiExt { name = "pi-foo"; version = "1.0.0"; owner = "..."; repo = "..."; rev = "v1.0.0"; srcHash = lib.fakeHash; outputHash = lib.fakeHash; };
}
