{ config, inputs, pkgs, lib, ... }:
{
  home.file = {
    ".config/zed/themes" = {
      recursive = true;
      source = ../dotfiles/zed/themes;
    };
  };
  programs.zed-editor = {
    enable = true;
    extraPackages = with pkgs; [
      nixd
      nixfmt
      prettierd
      pyright
      stylua
      lua-language-server
      vtsls
      clang
      clang-tools
      rust-analyzer
      cargo
      rustc
      yaml-language-server
      lldb
      prettierd
      vscode-langservers-extracted
      nil
      rustfmt
    ];
    extensions = [ "lua" "nix" "color highlight" ];
    userSettings = builtins.fromJSON (builtins.readFile ../dotfiles/zed/settings.json);
    userKeymaps = builtins.fromJSON (builtins.readFile ../dotfiles/zed/keymap.json);
    # mutableUserSettings = false;
    # mutableUserKeymaps = false;
  };
}
