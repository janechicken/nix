{ config, pkgs, inputs, lib, ... }:

let
  renixShell = import "${inputs.renix}/shell.nix" { inherit pkgs; };

  # Renix is a devShell — duplicates (e.g. gcc+clang both providing bin/c++,
  # gopls+gotools both providing bin/modernize) coexist via PATH ordering.
  # Home Manager's buildEnv rejects file collisions, so wrap everything in a
  # single buildEnv with ignoreCollisions for devShell-like last-wins behavior.
  renixBundle = pkgs.buildEnv {
    name = "renix-packages";
    paths = renixShell.buildInputs;
    ignoreCollisions = true;
  };
in {
  home.packages = [ renixBundle ];
}
