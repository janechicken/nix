{ config, pkgs, inputs, lib, ... }:
{
  imports = [
    inputs.nvchad4nix.homeManagerModule
  ];

  nixpkgs = { 
    overlays = [
      (final: prev: {
        nvchad = inputs.nvchad4nix.packages."${pkgs.system}".nvchad;
      })
    ];
  };

    programs.nvchad = {
      enable = true;
      extraPackages = with pkgs; [
        nixd
        nixfmt-classic
        prettierd
        pyright
        stylua
        lua-language-server
        vtsls
        clang
        clang-tools
        rust-analyzer
      ];
    };
}
