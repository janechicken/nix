{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:

{
  home.packages = with pkgs; [ any-nix-shell ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    dotDir = config.home.homeDirectory;
    envExtra = "export NOSYSZSHRC=1";
    shellAliases = {
      ls = "lsd -l";
      ll = "lsd -la";
      grep = "grep --color=auto";
      c = "clear";
      mkdir = "mkdir -p";
      spt = "spotify_player";
    };
    initContent = ''
      any-nix-shell zsh --info-right 2>/dev/null | source /dev/stdin
      export PS1=$'%{\e[255m%}%n%{\e[38;5;99m%}@%{\e[38;5;63m%}%M [%{\e[38;5;99m%}%~%{\e[38;5;63m%}]%{\e[37m%} $ %{\e[255m%}'

      # Ctrl keybinds for word movement and editing
      bindkey $'\e[1;5C' forward-word          # Ctrl+Right
      bindkey $'\e[1;5D' backward-word         # Ctrl+Left
      bindkey $'\e[1;5H' beginning-of-line     # Ctrl+Home
      bindkey $'\e[1;5F' end-of-line           # Ctrl+End
      bindkey $'\e[3;5~' kill-word             # Ctrl+Delete
      bindkey $'\b' backward-kill-word        # Ctrl+Backspace (^H/0x08)

      clear
      # Responsive fastfetch logo. Measured output widths of this config are
      # 108 columns with the full NixOS logo, 79 with `nixos_small` and 61
      # with no logo at all, so pick the widest one that still fits the
      # terminal (a half-screen tiled kitty lands in the `nixos_small`
      # bucket). `--disable-linewrap` turns the terminal's auto-wrap off
      # (DECAWM) for the duration of the run, so a long info line can never
      # wrap back over the logo.
      cols="''${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
      [[ "$cols" == <-> ]] || cols=80
      if [ "$cols" -ge 110 ]; then
        fastfetch --disable-linewrap
      elif [ "$cols" -ge 80 ]; then
        fastfetch -l nixos_small --disable-linewrap
      else
        fastfetch -l none --disable-linewrap
      fi
    '';
    completionInit = "autoload -U compinit && compinit -u";
  };
}
