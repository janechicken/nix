{ configs, inputs, pkgs, lib, ... }:
{
  home.packages = [ pkgs.stockfish pkgs.en-en-croissant ];
}
