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
      # Responsive fastfetch logo: always keep the NixOS icon, switching to
      # `nixos_small` below 110 columns (measured full-logo width is ~108 cols;
      # a half-screen tiled kitty at 1.25x is ~75-78 cols). `--disable-linewrap`
      # turns off terminal auto-wrap (DECAWM) for the run so long info lines
      # clip neatly at the right edge instead of wrapping back over the logo.
      cols="''${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
      [[ "$cols" == <-> ]] || cols=80
      if [ "$cols" -ge 110 ]; then
        fastfetch --disable-linewrap
      else
        fastfetch -l nixos_small --disable-linewrap
      fi
    '';
    completionInit = "autoload -U compinit && compinit -u";
  };
}
