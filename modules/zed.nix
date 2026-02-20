{ config, pkgs, lib, ... }:
{
  # Zed configuration
  programs.zed = {
    enable = true;
    extraPackages = with pkgs; [
      # Language servers and tools (Zed extensions or Nix packages)
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
      cargo
      rustc
      yaml-language-server
      lldb
      vscode-langservers-extracted
    ];

    # Zed theme: Convert Helix theme to Zed's TOML format
    theme = {
      # Custom color definitions
      color = {
        black = "#111111";
        brown = "#cfba8b";
        gray0 = "#090909";
        gray1 = "#0e0e0e";
        gray2 = "#1a1a1a";
        gray3 = "#404040";
        gray4 = "#626C66";
        gray5 = "#626C66";
        gray6 = "#aaaaaa";
        gray7 = "#c4c4c4";
        gray8 = "#e8e8e8";
        green = "#99be70";
        red = "#F05E48";
        turquoise1 = "#86c1b9";
        turquoise2 = "#72a59e";
        white1 = "#F3F2CC";
        white2 = "#F3F2CC";
        white3 = "#F3F2CC";
        white4 = "#7e7e7e";
      };

      # Syntax highlights
      syntax = {
        # Example: Highlight `function` as green
        "function" = { foreground = "green"; };
        # Add more syntax highlights as needed
      };

      # UI colors
      ui = {
        background = "gray0";
        foreground = "white1";
        cursor = "white1";
        statusbar = {
          background = "gray1";
          foreground = "white1";
        };
      };
    };

    # Zed keybindings
    keybindings = {
      # Example: Map "C-g" to a custom command
      "C-g" = "run-command :new\nrun-command :insert-output lazygit\nrun-command :buffer-close\nrun-command :redraw";
    };

    # Zed editor settings
    editor = {
      trueColor = true;
      whitespace = {
        renderSpace = true;
        renderTab = true;
      };
      statusbar = {
        showVersionControl = true;
        showFileEncoding = true;
      };
      inlineDiagnostics = {
        cursorLine = "warning";
      };
    };

    # LSP settings
    lsp = {
      displayMessages = false;
      displayInlayHints = true;
    };
  };
}
