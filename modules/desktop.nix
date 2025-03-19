{ config, inputs, pkgs, lib, ... }:

{
  # this assumes xorg and awesome are both already enabled in configuration.nix, this just copies the xinitrc and awesome config
  imports = 
  [
    ./librewolf.nix
    ./zsh.nix
  ];
      home.packages = with pkgs; [
      zsh
      any-nix-shell
      bibata-cursors
      kitty
      gnome-tweaks
      lxappearance
      keepassxc
      nemo
      playerctl
      killall
      btop
      ];

      home.file = {
        ".config/awesome" = { recursive = true; source = ../dotfiles/awesome; };
	".config/rofi" = { recursive = true; source = ../dotfiles/rofi; };
	".xinitrc" = { source = ../dotfiles/.xinitrc; };
	".config/picom" = { recursive = true; source = ../dotfiles/picom; };
      };

      home.sessionVariables = { EDITOR = "nvim"; VISUAL = "nvim"; MAKEFLAGS = "-j$(nproc)"; };
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

	programs.kitty = {
	  enable = true;
	  themeFile = "gruvbox-dark";
	  shellIntegration.enableZshIntegration = true;
	  settings = { connfirm_os_window_close = 0; enable_audio_bell = false; };
	};

	programs.rofi = { enable = true; plugins = [pkgs.rofi-emoji]; };

	dconf = { enable = true; settings = { "org/gnome/desktop/interface" = { color-scheme = "prefer-dark"; }; }; };

	gtk = {
	  enable = true;
	  theme = { name = "Adwaita"; };
	  cursorTheme = { name = "Bibata-Modern-Classic"; package = pkgs.bibata-cursors; };
	  iconTheme = { name = "Papirus"; package = pkgs.papirus-icon-theme; };
	};

	qt = { enable = true; platformTheme.name = "gtk"; style.name = "adwaita-dark"; };
}
