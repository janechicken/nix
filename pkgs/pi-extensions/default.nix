{ fetchFromGitHub, fetchurl, stdenv, nodejs, yarn, pnpm, jq, cacert, lib, python3, node-gyp, pkg-config, patchelf, nukeReferences }:

let
  # ---------------------------------------------------------------------------
  # Shared entry-point promotion: reads pi.extensions[0] from package.json and
  # promotes any nested file/directory to root, rewriting imports so they
  # still resolve.  This means the Pi builder never needs to be updated when a
  # new extension uses a different directory layout.
  # ---------------------------------------------------------------------------
  promoteEntryPoint = ''
    promote_entry_point() {
      local out="$1"

      local entry
      entry=$(jq -r '.pi.extensions[0] // ""' "$out/package.json" 2>/dev/null)

      # Nothing to do — no manifest entry, or already at root
      case "$entry" in
        ""|null|"./index.ts"|"./index.js") return 0 ;;
      esac

      # Strip leading ./
      local rel="''${entry#./}"

      # Still at root (entry was "index.ts" without ./prefix)
      case "$rel" in
        index.ts|index.js) return 0 ;;
      esac

      # If the entry is a directory, find index.ts or index.js inside
      if [ -d "$out/$rel" ]; then
        for f in index.ts index.js; do
          if [ -f "$out/$rel/$f" ]; then
            rel="$rel/$f"
            break
          fi
        done
      fi

      [ -f "$out/$rel" ] || return 0

      local subdir
      subdir=$(dirname "$rel")
      local ext="''${rel##*.}"
      local filename="index.$ext"

      # Read the canonical entry point from package.json, not our guess
      # (handles the case where the manifest points at a directory)
      local manifest_target
      manifest_target=$(jq -r '.pi.extensions[0] // ""' "$out/package.json")
      local pkg_rel="''${manifest_target#./}"

      # Copy to root
      cp "$out/$rel" "$out/$filename"

      # Rewrite relative imports so they still resolve after promotion:
      #   ./foo      →  ./$subdir/foo
      sed -i \
        -e "s|from '\\./|from './$subdir/|g" \
        -e 's|from "\./|from "./'$subdir'/|g' \
        -e "s|require('\\./|require('./$subdir/|g" \
        -e 's|require("\./|require("./'$subdir'/|g' \
        "$out/$filename"

      #   ../foo     →  ./$parent/foo  (or ./foo if parent is root)
      local parent
      parent=$(dirname "$subdir")
      if [ "$parent" = "." ]; then
        sed -i \
          -e "s|from '\\.\\./|from './|g" \
          -e 's|from "\.\./|from "./|g' \
          -e "s|require('\\.\\./|require('./|g" \
          -e 's|require("\.\./|require("./|g' \
          "$out/$filename"
      else
        sed -i \
          -e "s|from '\\.\\./|from './$parent/|g" \
          -e 's|from "\.\./|from "./'$parent'/|g' \
          -e "s|require('\\.\\./|require('./$parent/|g" \
          -e 's|require("\.\./|require("./'$parent'/|g' \
          "$out/$filename"
      fi

      # Remove the nested copy so Pi doesn't discover it separately
      rm -f "$out/$rel"

      # Relocate resources/ from the promoted subdirectory to root, so bundled
      # assets like skills remain discoverable at the expected paths.
      if [ -d "$out/$subdir/resources" ]; then
        cp -r "$out/$subdir/resources" "$out/"
        rm -rf "$out/$subdir/resources"
      fi

      # Update package.json to point at the now-root entry point
      sed -i 's|"'"$rel"'"|"./'"$filename"'"|g' "$out/package.json"
    }
  '';

in rec {

  # -----------------------------------------------------------------------
  # Build an extension from a GitHub repo (yarn or pnpm).
  # -----------------------------------------------------------------------
  mkPiExt = { name, version, owner, repo, rev, srcHash, outputHash, pkgManager ? "yarn", extraInstallCommands ? "" }:
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
      nativeBuildInputs = [ nodejs pm jq cacert python3 ];
      env = {
        # Prevent node-gyp from rebuilding native addons in FOD builds.
        npm_config_build_from_source = "false";
      };
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
        rm -rf "$out/.npm" "$out/.cache" "$out/node_modules/.cache" 2>/dev/null || true
        ${promoteEntryPoint}
        promote_entry_point "$out"
        ${extraInstallCommands}
      '';
    };

  # -----------------------------------------------------------------------
  # Build an extension from an npm tarball.
  # -----------------------------------------------------------------------
  mkNpmPiExt = { name, version, tarballUrl, tarballHash, outputHash, extraInstallCommands ? "" }:
    stdenv.mkDerivation {
      pname = name;
      inherit version;
      src = fetchurl {
        url = tarballUrl;
        hash = tarballHash;
      };
      nativeBuildInputs = [ nodejs yarn jq cacert python3 node-gyp pkg-config patchelf nukeReferences ];
      dontFixup = true;
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      inherit outputHash;
      sourceRoot = "package";
      buildPhase = ''
        # node_modules/.bin is added to PATH so lifecycle scripts (prebuild-install,
        # node-gyp) are found during yarn install.
        export PATH="$PWD/node_modules/.bin:$PATH"
        NIX_SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt \
        HOME=$TMPDIR yarn install --prod --no-progress --non-interactive --ignore-engines 2>&1
      '';
      installPhase = ''
        mkdir -p "$out"
        cp -r . "$out/"
        rm -rf "$out/.npm" "$out/.cache" "$out/node_modules/.cache" 2>/dev/null || true
        rm -f "$out/yarn.lock" 2>/dev/null || true
        # FODs must not reference store paths. Strip debug info and RPATH
        # from compiled native addons (better-sqlite3 and similar) to remove
        # embedded references to python3, gcc, etc.
        find "$out" -type f -name "*.node" -exec patchelf --remove-rpath {} \; 2>/dev/null || true
        find "$out" -type f -name "*.so" -exec patchelf --remove-rpath {} \; 2>/dev/null || true
        find "$out" -type f -name "*.node" -exec strip --strip-unneeded {} \; 2>/dev/null || true
        find "$out" -type f -name "*.so" -exec strip --strip-unneeded {} \; 2>/dev/null || true
        # Remove any remaining textual store path references
        find "$out" -type f -exec nuke-refs {} \; 2>/dev/null || true
        # Clean up intermediate build artifacts from native addon builds
        find "$out" -type d -name ".deps" -prune -exec rm -rf {} \; 2>/dev/null || true
        find "$out" -name "*.o" -o -name "*.obj" -o -name "*.d" | xargs rm -f 2>/dev/null || true
        ${promoteEntryPoint}
        promote_entry_point "$out"
        ${extraInstallCommands}
      '';
    };

  # -----------------------------------------------------------------------
  # Installed extensions — add new ones here, never touch the builders above.
  # -----------------------------------------------------------------------
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
    outputHash = "sha256-zrE1Wx5i89FQQFw5j7TIspsjxLKL75L/dq2S9NwUXp0=";
  };

  pi-hermes-memory = mkNpmPiExt {
    name = "pi-hermes-memory";
    version = "0.7.14";
    tarballUrl = "https://registry.npmjs.org/pi-hermes-memory/-/pi-hermes-memory-0.7.14.tgz";
    tarballHash = "sha256-RTPu8NZHoBJcCvgDihTD31GJo5mFS+ey/fTPhcg4goA=";
    outputHash = "sha256-Zt1pQZ5V0a/ocBU9xo+wxtpVCJ6p1wHIp3RCW0Ejazs=";
  };

  pi-advisor = mkNpmPiExt {
    name = "pi-advisor";
    version = "0.3.0";
    tarballUrl = "https://registry.npmjs.org/pi-advisor/-/pi-advisor-0.3.0.tgz";
    tarballHash = "sha256-zZlgH2JmkOPKKpwKz7ZwWpabEZCtVTPWcC2jDzdLshM=";
    outputHash = "sha256-cBydqkkOmoOTgbyfHCWI3AbVaNahqEq4Ql6T4g6FQXo=";
  };

  pi-ask-user = mkNpmPiExt {
    name = "pi-ask-user";
    version = "0.11.2";
    tarballUrl = "https://registry.npmjs.org/pi-ask-user/-/pi-ask-user-0.11.2.tgz";
    tarballHash = "sha256-cgCViWrwsGmE/qJvNPmNMZIV3os6/AsS7zJf0+lOaB8=";
    outputHash = "sha256-p0JE7VnydMOhz3lFBpqVtMkntkCPAaN6hWNTmfA4ZPM=";
  };

  pi-timestamps = mkNpmPiExt {
    name = "pi-timestamps";
    version = "0.1.0";
    tarballUrl = "https://registry.npmjs.org/pi-timestamps/-/pi-timestamps-0.1.0.tgz";
    tarballHash = "sha256-ZKKKEBvLSij2vHJ9zJa4CwUkQYjYUMXh3hiPhl7sKlI=";
    outputHash = "sha256-s6KGE5IUrN+oHss5wLTr73hZW1atnbIJ/TPCyHKIKdg=";
    extraInstallCommands = ''
      echo 'export { default } from "./timestamps.ts";' > "$out/extensions/index.ts"
    '';
  };

  pi-neuralwatt = mkPiExt {
    name = "pi-neuralwatt";
    version = "0.7.2";
    owner = "aliou";
    repo = "pi-neuralwatt";
    rev = "v0.7.2";
    srcHash = "sha256-2rhA9td+1Y5rmjcRBdvfIperugtiZKzVUTk4VJDPOHQ=";
    pkgManager = "pnpm";
    outputHash = "sha256-SE7IHYK9rgxiI3fXHZUqep9Gtfz9B+2WdSa+G0zGZMM=";
    extraInstallCommands = ''
      echo 'export { default } from "./src/extensions/command-quotas/index.ts";' > "$out/neuralwatt-quotas.ts"
      echo 'export { default } from "./src/extensions/quota-warnings/index.ts";' > "$out/neuralwatt-warnings.ts"
      echo 'export { default } from "./src/extensions/sub-bar-integration/index.ts";' > "$out/neuralwatt-sub-bar.ts"
    '';
  };
}
