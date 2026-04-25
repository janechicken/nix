{ config, pkgs, inputs, lib, ... }:

let
  renixShell = import "${inputs.renix}/shell.nix" { inherit pkgs; };

  renixBundle = pkgs.buildEnv {
    name = "renix-packages";
    paths = renixShell.buildInputs;
    ignoreCollisions = true;
  };
in {
  home.packages = [ renixBundle pkgs.feroxbuster pkgs.seclists pkgs.waybackurls pkgs.katana ];
}
