{ fetchFromGitHub, fetchurl, stdenv, nodejs, yarn, pnpm, jq, cacert, lib }:

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
        -e "s|from '\\./|from '$subdir/|g" \
        -e 's|from "\./|from "'$subdir'/|g' \
        -e "s|require('\\./|require('$subdir/|g" \
        -e 's|require("\./|require("'$subdir'/|g' \
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
          -e "s|from '\\.\\./|from '$parent/|g" \
          -e 's|from "\.\./|from "'$parent'/|g' \
          -e "s|require('\\.\\./|require('$parent/|g" \
          -e 's|require("\.\./|require("'$parent'/|g' \
          "$out/$filename"
      fi

      # Remove the nested copy so Pi doesn't discover it separately
      rm -f "$out/$rel"

      # Update package.json to point at the now-root entry point
      sed -i 's|"'"$rel"'"|"./'"$filename"'"|g' "$out/package.json"
    }
  '';

in rec {

  # -----------------------------------------------------------------------
  # Build an extension from a GitHub repo (yarn or pnpm).
  # -----------------------------------------------------------------------
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
      nativeBuildInputs = [ nodejs pm jq cacert ];
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
      '';
    };

  # -----------------------------------------------------------------------
  # Build an extension from an npm tarball.
  # -----------------------------------------------------------------------
  mkNpmPiExt = { name, version, tarballUrl, tarballHash, outputHash }:
    stdenv.mkDerivation {
      pname = name;
      inherit version;
      src = fetchurl {
        url = tarballUrl;
        hash = tarballHash;
      };
      nativeBuildInputs = [ nodejs yarn jq cacert ];
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
        rm -f "$out/yarn.lock" 2>/dev/null || true
        ${promoteEntryPoint}
        promote_entry_point "$out"
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
    outputHash = "sha256-a5YicKQvRNbMJ6m41C8qgQyNjII5ZsAVvPba/evaK8Q=";
  };

  pi-hermes-memory = mkNpmPiExt {
    name = "pi-hermes-memory";
    version = "0.7.13";
    tarballUrl = "https://registry.npmjs.org/pi-hermes-memory/-/pi-hermes-memory-0.7.13.tgz";
    tarballHash = "sha256-B9A1rjiUZRuZh+cyPe3cwchzc6Av72pEjFvzrawAr+E=";
    outputHash = "sha256-RHl0KXE+EEz2JA+X8kuhnWMBIQJ2JoofiSjFPQC7lbM=";
  };

  piolium = mkNpmPiExt {
    name = "piolium";
    version = "0.0.8";
    tarballUrl = "https://registry.npmjs.org/@vigolium/piolium/-/piolium-0.0.8.tgz";
    tarballHash = "sha256-Gu5IHVDJDgMKiCKkeAoW6pgRM6BEDuqFKNfnvKwJeps=";
    outputHash = "sha256-y53djTt9IeZGZe4v9j3G4FVDe/QMXmp7pIPbNyZg3Vc=";
  };

  pi-markdown-preview = mkNpmPiExt {
    name = "pi-markdown-preview";
    version = "0.9.9";
    tarballUrl = "https://registry.npmjs.org/pi-markdown-preview/-/pi-markdown-preview-0.9.9.tgz";
    tarballHash = "sha256-y1TwhNvgDL6kF+oP+AmtjwNczkjMw69Xtajuie3mlkc=";
    outputHash = "sha256-0ulgk83qWY1AmVDFJqKiH/xXIaTwJ1iKTbGH5kqvjSk=";
  };

  pi-intercom = mkNpmPiExt {
    name = "pi-intercom";
    version = "0.6.0";
    tarballUrl = "https://registry.npmjs.org/pi-intercom/-/pi-intercom-0.6.0.tgz";
    tarballHash = "sha256-dsDVKEZhqsQ3JIu2x6Moef6GMpa9FctTN1GyfK/ESBg=";
    outputHash = "sha256-nwt6JjcMaMCZMP1WYuT5aZU6WqeUyIwuQdtOPJRQyTc=";
  };
}
