{ fetchFromGitHub, stdenv, nodejs, yarn, cacert, lib }:

let
  mkPiExt = { name, version, owner, repo, rev, srcHash, outputHash }:
    stdenv.mkDerivation {
      pname = name;
      inherit version;
      src = fetchFromGitHub {
        inherit owner repo rev;
        hash = srcHash;
      };
      nativeBuildInputs = [ nodejs yarn cacert ];
      dontFixup = true;
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      inherit outputHash;
      buildPhase = ''
        NIX_SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt \
        HOME=$TMPDIR yarn install --production --no-progress --non-interactive 2>&1
      '';
      installPhase = ''
        mkdir -p "$out"
        cp -r . "$out/"
        rm -rf "$out/.npm" "$out/.cache" 2>/dev/null || true
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
    outputHash = "sha256-K9sUHfWt9QgriMFzrH0zJ9kBHdTAc9180A+GLttltxY=";
  };

  pi-subagents = mkPiExt {
    name = "pi-subagents";
    version = "0.25.0";
    owner = "nicobailon";
    repo = "pi-subagents";
    rev = "v0.25.0";
    srcHash = "sha256-eHz/uivSIZ8HOalSCZgyCyOWodQJq5GapAqpT2ryn1k=";
    outputHash = "sha256-NNmk95R20EJSeYsNEWe2qByATe52SFlw/e+/AAZt2To=";
  };

  pi-mcp-adapter = mkPiExt {
    name = "pi-mcp-adapter";
    version = "2.8.0";
    owner = "nicobailon";
    repo = "pi-mcp-adapter";
    rev = "v2.8.0";
    srcHash = "sha256-eHz/uivSIZ8HOalSCZgyCyOWodQJq5GapAqpT2ryn1k=";
    outputHash = "sha256-NNmk95R20EJSeYsNEWe2qByATe52SFlw/e+/AAZt2To=";
  };

  # Add more:
  # pi-foo = mkPiExt { name = "pi-foo"; version = "1.0.0"; owner = "..."; repo = "..."; rev = "v1.0.0"; srcHash = lib.fakeHash; outputHash = lib.fakeHash; };
}
