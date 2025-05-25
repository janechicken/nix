# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, inputs, ... }:

{
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/fonts.nix
    inputs.yeetmouse.nixosModules.default
    ../../modules/core.nix
    ../../modules/fido.nix
    ../../modules/udiskie.nix
    ../../modules/reaper.nix
    ../../modules/audio.nix
    ../../modules/steam.nix
  ];

  hardware.yeetmouse = {
    enable = true;
    sensitivity = 0.25;
    outputCap = 5.0;
    # offset = 0.0;
    inputCap = 20.0;
  };

  system.autoUpgrade.enable = true;
  system.autoUpgrade.allowReboot = true;

  # Use the systemd-boot EFI boot loader.
  boot = {
    initrd = {
      kernelModules = [ "i915" ];
      systemd.enable = true;
      luks.devices."cryptroot".crypttabExtraOpts = [ "fido2-device=auto" ];
    };
    kernelPackages = pkgs.linuxPackages_latest;
  };
  boot.loader = {
    grub = {
      enable = true;
      enableCryptodisk = true;
      useOSProber = true;
      efiSupport = true;
      copyKernels = true;
      device = "nodev";
      extraEntries = ''
        menuentry "Reboot" {
            reboot
        }
        menuentry "Poweroff" {
            halt
        }
      '';
    };
    efi = {
      canTouchEfiVariables = true;
      #efiSysMountPoint = "/boot/efi";
    };
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.hostName = "octo-pc"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable =
    true; # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;
    autorun = false;
    displayManager.startx = { enable = true; };
    windowManager.awesome = {
      enable = true;
      luaModules = with pkgs.luaPackages; [ luarocks luadbi-mysql vicious ];
    };
  };
  hardware.opengl = {
    enable = true;
    driSupport32Bit = true;
  };
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ vpl-gpu-rt vaapiIntel intel-media-driver nvidia-vaapi-driver vaapiVdpau libvdpau-va-gl ];
  };
  hardware.nvidia = {
    open = true;
    modesetting.enable = false;
    powerManagement.enable = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  services = {
    displayManager.defaultSession = "none+awesome";
    picom = {
      enable = true;
      backend = "glx";
      shadow = true;
      vSync = true;
    };
    udev.packages = [ pkgs.yubikey-personalization ];
    syncthing = {
      enable = true;
      user = "octo";
      dataDir = "/home/octo";
      configDir = "/home/octo/.config/syncthing";
      openDefaultPorts = true;
      settings.gui = {
        user = "admin";
        password = "admin";
      };
      settings.devices = {
        "phone" = {
          id =
            "ZGE6ZIT-632YYAI-CJFGW4Z-VQQYQWI-XQ5BIIP-2N6OWRX-FOOZINA-AMPD6QC";
        };
      };
      settings.folders = {
        "sync" = {
          path = "/home/octo/sync";
          devices = [ "phone" ];
          ignorePerms = true;
        };
      };
    };
    input-remapper.enable = true;
  };

  programs.zsh.enable = true;

  # Configure keymap in X11
  services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # OR

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.octo = {
    isNormalUser = true;
    extraGroups = [ "wheel" "input" "networkmanager" "audio" ];
    shell = pkgs.zsh;
  };

  # programs.firefox.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    xorg.xorgserver
    xorg.xf86inputevdev
    xorg.xf86inputsynaptics
    xorg.xf86inputlibinput
    alsa-utils
    dconf
    adwaita-icon-theme
    alsa-lib
    cudatoolkit
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.05"; # Did you read the comment?

}

