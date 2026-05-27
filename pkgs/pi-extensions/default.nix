{ buildNpmPackage, fetchurl, fetchFromGitHub, lib }:

let
  mkPiExt = { name, version, src, npmDepsHash }:
    buildNpmPackage {
      pname = name;
      inherit version src npmDepsHash;
      dontNpmBuild = true;
      installPhase = ''
        mkdir -p "$out"
        cp -r . "$out/"
      '';
    };

  mkPiExtNpm = { name, version, hash, npmDepsHash }:
    mkPiExt {
      inherit name version npmDepsHash;
      src = fetchurl {
        url = "https://registry.npmjs.org/${name}/-/${name}-${version}.tgz";
        inherit hash;
      };
    };

  mkPiExtGit = { name, version, owner, repo, rev, hash, npmDepsHash }:
    mkPiExt {
      inherit name version npmDepsHash;
      src = fetchFromGitHub {
        inherit owner repo rev hash;
      };
    };
in {
  pi-web-access = mkPiExtGit {
    name = "pi-web-access";
    version = "0.10.7";
    owner = "nicobailon";
    repo = "pi-web-access";
    rev = "v0.10.7";
    hash = "sha256-D9no4SLigH/t3/WfirixMbTEjcEwZwJXld8j7pwBCew=";
    npmDepsHash = "sha256-QKmgVmIvqLbqnUmKBKniT0CvNIgZWZ9mUkha0LJMMVQ=";
  };

  # Add more extensions below:
  # foo-ext = mkPiExtGit { ... };
  # bar-ext = mkPiExtNpm { ... };  # if package ships lockfile in tarball
}
