{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
{
  home.file = {
    ".config/zed/" = {
      recursive = true;
      source = ../dotfiles/zed;
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
    ];
    # mutableUserSettings = false;
    # mutableUserKeymaps = false;
  };
}
