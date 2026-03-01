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
    ];
    extensions = [ "lua" "nix" "color highlight" ];
    userSettings = builtins.fromJSON (builtins.readFile ../dotfiles/zed/settings.json);
    userKeymaps = builtins.fromJSON (builtins.readFile ../dotfiles/zed/keymap.json);
    mutableUserSettings = false;
    mutableUserKeymaps = false;
  };

  home.file.".local/bin/zed" = {
    text = ''
      #!/bin/sh
      # Read DeepSeek API key if the file exists
      if [ -f "$HOME/.config/zed/deepseek_api_key" ]; then
        export DEEPSEEK_API_KEY="$(cat "$HOME/.config/zed/deepseek_api_key")"
      fi
      # Execute the real zeditor binary from the wrapped package
      exec ${config.programs.zed-editor.package}/bin/.zeditor-wrapped "$@"
    '';
    executable = true;
  };

  home.file.".local/bin/zeditor" = {
    text = ''
      #!/bin/sh
      # Read DeepSeek API key if the file exists
      if [ -f "$HOME/.config/zed/deepseek_api_key" ]; then
        export DEEPSEEK_API_KEY="$(cat "$HOME/.config/zed/deepseek_api_key")"
      fi
      # Execute the real zeditor binary from the wrapped package
      exec ${config.programs.zed-editor.package}/bin/.zeditor-wrapped "$@"
    '';
    executable = true;
  };

  # Create our own desktop entry that overrides the system one
  xdg.desktopEntries."dev.zed.Zed" = {
    name = "Zed";
    genericName = "Code Editor";
    exec = "${config.home.homeDirectory}/.local/bin/zeditor %U";
    icon = "zed";
    terminal = false;
    type = "Application";
    categories = [ "Development" "TextEditor" ];
    mimeType = [ "text/plain" "inode/directory" ];

  };
}
