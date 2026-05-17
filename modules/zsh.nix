{ config, inputs, pkgs, lib, ... }:

{
  home.packages = with pkgs; [ any-nix-shell helix-driver ];

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
    initExtra = ''
       	  any-nix-shell zsh --info-right 2>/dev/null | source /dev/stdin
          export PS1=$'%{\e[255m%}%n%{\e[38;5;99m%}@%{\e[38;5;63m%}%M [%{\e[38;5;99m%}%~%{\e[38;5;63m%}]%{\e[37m%} $ %{\e[255m%}'
          source ${pkgs.helix-driver}/share/helix-zsh/helix_zsh.zsh
          clear
       	  fastfetch
       	  '';
    completionInit = "autoload -U compinit && compinit -u";
  };
}
