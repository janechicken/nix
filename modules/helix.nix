{ config, inputs, pkgs, lib, ... }:
{
  programs.helix = {
    enable = true;
    defaultEditor = true;
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
        cargo
        rustc
        ];
    themes = {
      autumn-dark-custom = let
        my_black      = "#111111";
        my_brown      = "#cfba8b";
        my_gray0      = "#090909";
        my_gray1      = "#0e0e0e";
        my_gray2      = "#1a1a1a";
        my_gray3      = "#404040";
        my_gray4      = "#626C66"; # Inlay-hint
        my_gray5      = "#626C66"; # Comments, Invisibles, Line Highlighting
        my_gray6      = "#aaaaaa"; # Dark Foreground (Used for status bars)
        my_gray7      = "#c4c4c4"; # Light Foreground
        my_gray8      = "#e8e8e8"; # Light Background
        my_green      = "#99be70"; # Strings, Inherited Class, Markup Code, Diff Inserted
        my_red        = "#F05E48"; # Keywords, Storage, Selector, Diff Changed
        my_turquoise1 = "#86c1b9"; # Support, Regular Expressions, Escape Characters
        my_turquoise2 = "#72a59e"; # URL
        my_white1     = "#F3F2CC"; # Default Foreground, Caret, Delimiters, Operators
        my_white2     = "#F3F2CC"; # Variables, XML Tags, Markup Link Text, Markup Lists, Diff Deleted
        my_white3     = "#F3F2CC"; # Classes, Markup Bold, Search Text Background
        my_white4     = "#7e7d6a"; # Secondary cursors
        my_yellow1    = "#FAD566"; # Functions, Methods, Attribute IDs, Headings
        my_yellow2    = "#ffff9f"; # Debug, Info
        in {
          "attribute" = my_turquoise1;
          "comment" = { fg = my_gray5; modifiers = ["italic"]; };
          "constant.character.escape" = my_turquoise1;
          "constant" = my_white3;
          "constant.numeric" = my_turquoise1;
          "constructor" = my_yellow1;
          "debug" = my_yellow2;
          "diagnostic.error" = { underline = { style = "curl"; color = my_red; }; };
          "diagnostic.hint" = { underline = { style = "line"; color = my_gray5; }; bg = my_black; };
          "diagnostic.info" = { underline = { style = "line"; }; };
          "diagnostic" = { underline = { style = "line"; color = my_gray5; }; bg = my_black; };
          "diagnostic.warning" = { underline = { style = "curl"; color = my_yellow2; }; };
          "diagnostic.unnecessary" = { modifiers = ["dim"]; };
          "diagnostic.deprecated" = { modifiers = ["crossed_out"]; };
          "diff.delta" = my_gray5;
          "diff.minus" = my_red;
          "diff.plus" = my_green;
          "error" = my_red;
          "function" = my_yellow1;
          "hint" = my_gray6;
          "info" = my_yellow2;
          "keyword" = { fg = my_red; modifiers = ["bold" "italic"]; };
          "label" = my_red;
          "markup.bold" = { modifiers = ["bold"]; };
          "markup.heading" = my_yellow1;
          "markup.italic" = { modifiers = ["italic"]; };
          "markup.link.text" = my_white2;
          "markup.link.url" = my_turquoise2;
          "markup.list" = my_white2;
          "markup.quote" = my_brown;
          "markup.raw" = my_green;
          "markup.strikethrough" = { modifiers = ["crossed_out"]; };
          "namespace" = my_white3;
          "operator" = my_white1;
          "special" = my_yellow1;
          "string"  = my_green;
          "type" = { fg = my_white3; modifiers = ["italic"]; };
          "ui.background" = { bg = my_gray0; };
          "ui.cursor" = { bg = my_white4; fg = my_black; };
          "ui.cursorline" = { bg = my_gray3; };
          "ui.cursorline.primary" = { bg = my_black; };
          "ui.cursorline.secondary" = { bg = my_black; };
          "ui.cursor.match" = { fg = my_white1; modifiers = ["bold"]; underline = { style = "double_line"; color = my_white1; }; bg = my_black; };
          "ui.cursor.primary" = { fg = my_white1; modifiers = ["reversed"]; };
          "ui.debug" = { fg = my_yellow1; bg = my_gray0; };
          "ui.gutter" = { bg = my_gray0; };
          "ui.help" = { fg = my_gray7; bg = my_gray2; };
          "ui.highlight.frameline" = { bg = "#8b6904"; };
          "ui.linenr" = { fg = my_gray3; bg = my_gray0; };
          "ui.linenr.selected" = { fg = my_gray7; bg = my_gray0; };
          "ui.menu" = { fg = my_white1; bg = my_gray2; };
          "ui.menu.selected" = { fg = my_gray2; bg = my_gray6; };
          "ui.popup" = { bg = my_gray2; };
          "ui.selection" = { bg = my_gray3; };
          "ui.statusline" = { fg = my_gray7; bg = my_gray2; };
          "ui.statusline.inactive" = { fg = my_gray5; bg = my_gray2; };
          "ui.statusline.insert" = { fg = my_black; bg = my_gray6; modifiers = ["bold"]; };
          "ui.statusline.normal" = { fg = my_gray7; bg = my_gray2; };
          "ui.statusline.select" = { fg = my_gray7; bg = my_black; modifiers = ["bold"]; };
          "ui.text.focus" = my_white1;
          "ui.text" = my_white1;
          "ui.virtual.inlay-hint" = { fg = my_gray4; bg = my_black; }; #, modifiers = ["normal"] };
          "ui.virtual.inlay-hint.parameter" = my_gray4;
          "ui.virtual.inlay-hint.type" = { fg = my_gray4; modifiers = ["italic"]; };
          "ui.virtual.jump-label" = { fg = my_yellow2; modifiers = ["bold"]; };
          "ui.virtual.ruler" = { bg = my_gray1; };
          "ui.virtual.whitespace" = { fg = my_gray6; };
          "ui.virtual.wrap" = my_gray4;
          "ui.window" = { fg = my_gray3; bg = my_gray2; };
          "variable" = my_white3;
          "variable.other.member" = my_brown;
          "warning" = my_yellow2;
        };
    };
    settings = {
      theme = "autumn-dark-custom";
      keys.normal = {
        esc = ["collapse_selection" "keep_primary_selection"];
        up = "no_op";
        down = "no_op";
        left = "no_op";
        right = "no_op";
      };
      keys.insert = {
        up = "no_op";
        down = "no_op";
        left = "no_op";
        right = "no_op";
      };
      editor = {
        mouse = true;
        clipboard-provider = "x-clip";
        file-picker.hidden = false;
        end-of-line-diagnostics = "hint";
        true-color = true;
        color-modes = true;
        auto-pairs = true;
        completion-trigger-len = 1;
        cursorline = true;
        bufferline = "multiple";
        shell = [ "zsh" "-c" ];
        cursor-shape.insert = "bar";
        cursor-shape.normal = "block";
        cursor-shape.select = "underline";
        whitespace.characters = {
          space = " ";
          tab = "→";
        };
        whitespace.render.space = "all";
        whitespace.render.tab = "all";
        indent-guides = {
          render = true;
          character = "▏";
          skip-levels = 1;
        };
        gutters = ["diff" "diagnostics" "line-numbers" "spacer"];
        lsp = {
          display-messages = true;
          display-inlay-hints = true;
        };
        statusline = {
          left = ["mode" "separator" "file-name" "read-only-indicator" "file-modification-indicator"];
          center = ["version-control" "spinner"];
          right = ["diagnostics" "workspace-diagnostics" "register" "position" "file-encoding"];
          separator = "|";
          mode.normal = "NORMAL";
          mode.insert = "INSERT";
          mode.select = "SELECT";
        };
        inline-diagnostics = {
          cursor-line = "warning";
        };
      };
    };
  };
}
