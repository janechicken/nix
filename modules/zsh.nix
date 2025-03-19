{ config, inputs, pkgs, lib, ... }:

{
      home.packages = with pkgs; [
        any-nix-shell
      ];

      programs.zsh = {
        enable = true;
	enableCompletion = true;
	autosuggestion.enable = true;
	syntaxHighlighting.enable = true;
	shellAliases = {
          ls = "lsd -l";
      	  ll = "lsd -la";
      	  grep = "grep --color=auto";
      	  c = "clear";
      	  mkdir = "mkdir -p";
      	  spt = "spotify_player";
      	  update = "sudo nixos-rebuild switch";
    	  }; 
    	  initExtra = ''
    	  any-nix-shell zsh --info-right | source /dev/stdin
    	  export PS1=$'%{\e[255m%}%M%{\e[38;5;99m%}@%{\e[38;5;63m%}%n [%{\e[38;5;99m%}%~%{\e[38;5;63m%}] %{\e[36m%}%{\e[2m%}%{\e[0m%}(%?) > %{\e[255m%}'
    	  fastfetch
    	  '';
	};
}
