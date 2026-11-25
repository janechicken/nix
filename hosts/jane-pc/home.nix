{
  config,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ../../modules/desktop.nix
    ../../modules/hyprland-home.nix
    ../../modules/creative.nix
    ../../modules/git.nix
    ../../modules/spotify.nix
    ../../modules/discord.nix
    ../../modules/crypto.nix
    ../../modules/cemu.nix
    ../../modules/hex.nix
    ../../modules/minecraft.nix
    ../../modules/gpg.nix
    ../../modules/u2f-keys.nix
    ../../modules/dolphin.nix
    ../../modules/chess.nix
    ../../modules/zed.nix
    ../../modules/pi.nix
    ../../modules/t3code.nix
    ../../modules/antigravity.nix
    ../../modules/messaging.nix
    ../../modules/syncthing.nix
    ../../modules/obsidian.nix
    ../../modules/renix.nix
    ../../secrets/home-secrets.nix
  ];
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "jane";
  home.homeDirectory = "/home/jane";
  nixpkgs.config.permittedInsecurePackages = [
    "python3.13-ecdsa-0.19.2"
    "python3.14-ecdsa-0.19.2"
  ];

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.05"; # Please read the comment before changing.

  # Hyprland: same look & feel as yogabook. Monitors mirror the old .xinitrc
  # xrandr layout (DP-3 165Hz primary at 0x0, DP-1 to its right), desktop so no
  # backlight/swipe/battery, and VRR only in fullscreen (2) to match the old
  # `Option "VariableRefresh" "True"` on the 165Hz panel without stuttering the
  # 60Hz secondary. No idle lock/DPMS timeouts: jane-pc only locks on suspend.
  custom.hyprland = {
    monitors = [
      {
        output = "DP-3";
        mode = "1920x1080@165";
        position = "0x0";
        scale = 1;
      }
      {
        output = "DP-1";
        # Hyprland's mode parser rejects `1920x1080@preferred` (the refresh
        # part must be a number), and a bare `1920x1080` would pin 60Hz. The
        # old xrandr line used `--mode 1920x1080` with no rate, i.e. the
        # monitor's EDID-preferred mode.
        mode = "preferred";
        position = "1920x0";
        scale = 1;
      }
    ];
    isLaptop = false;
    vrr = 2;
    idleLockTimeout = null;
    idleDpmsTimeout = null;
  };

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides to package configurations. You can do that directly here,
    # # just don't forget the parentheses.
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'. (The old X11 `.xinitrc` is gone: the
  # session is started by Hyprland's wayland-session entry.)

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/jane/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = { };

  # Create and manage the standard user directories (Desktop, Documents,
  # Downloads, Music, Pictures, Public, Templates, Videos). Non-destructive:
  # only mkdir -p's any that are absent + writes the user-dirs.dirs pointer.
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    setSessionVariables = false; # deprecated in home-manager; keep off
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
