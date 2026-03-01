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
      # Execute the real zed binary
      exec ${config.programs.zed-editor.package}/bin/zed "$@"
    '';
    executable = true;
  };

  home.activation.fixZedDesktopEntry = lib.hm.dag.entryAfter ["writeBoundary"] ''
    DESKTOP_FILE="$HOME/.nix-profile/share/applications/zed.desktop"
    if [ -f "$DESKTOP_FILE" ]; then
      # Backup the original
      cp "$DESKTOP_FILE" "$DESKTOP_FILE.backup"
      # Replace Exec line to use our wrapper
      sed -i 's|^Exec=.*|Exec=$HOME/.local/bin/zed %F|' "$DESKTOP_FILE"
      echo "Updated desktop entry to use zed wrapper with DEEPSEEK_API_KEY"
    else
      echo "Warning: zed.desktop not found at $DESKTOP_FILE"
    fi
  '';
}
