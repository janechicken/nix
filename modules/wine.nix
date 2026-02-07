{ config, inputs, pkgs, lib, ... }:
let
  wine-adobe = pkgs.stdenv.mkDerivation {
    pname = "wine-adobe";
    version = "custom-adobe-patch";
    src = pkgs.fetchurl {
      url =
        "https://github.com/PhialsBasement/wine-adobe-installers/releases/download/fix-dropdowns/bleeding-edge-local.tar.gz";
      sha256 =
        "sha256:d383b940b5ba49d497f98c6c44d306277e10b2f8cb6104a9470f75599993a704";
    };
  };
in { environment.systemPackages = [ wine-adobe ]; }
