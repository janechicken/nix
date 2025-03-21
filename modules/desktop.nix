{ config, inputs, pkgs, lib, ... }:

{
  # this assumes xorg and awesome are both already enabled in configuration.nix, this just copies the xinitrc and awesome config
  imports = 
  [
    ./librewolf.nix
    ./zsh.nix
  ];
  

      nixpkgs.config = { allowBroken = true; allowUnfree = true; };

      home.packages = with pkgs; [
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

	programs.kitty = {
	  enable = true;
	  themeFile = "gruvbox-dark-hard";
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
	  gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    	  gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
	};

	qt = { enable = true; platformTheme.name = "gtk"; style.name = "adwaita-dark"; };
}
