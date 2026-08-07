# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# Lenovo Yoga Slim 7 14Q8Y11 — Snapdragon X2 Elite (X2E-88-100), aarch64.
# Linux on X2 is young (mainline enablement landed in kernel 6.19): expect
# rough edges. Reference for the same laptop family: kuruczgy/x1e-nixos-config
# (X1E Yoga Slim 7x). Windows on ARM remains the mature OS on this hardware.

{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/fonts.nix
    ../../modules/core.nix
    ../../modules/fido.nix
    ../../modules/udiskie.nix
    ../../modules/reaper.nix
    ../../modules/audio.nix
    ../../modules/keyring.nix
    ../../modules/flatpak.nix
    ../../modules/nix-ld.nix
    ../../modules/networking.nix
    ../../modules/xdg-portal.nix
    ../../modules/lock.nix
    inputs.sops-nix.nixosModules.sops
    ../../secrets/sops-nix.nix
  ];

  services.udev.packages = [
    pkgs.yubikey-personalization
  ];

  services.udev.extraRules = ''
    # 2.4GHz/Dongle
    KERNEL=="hidraw*", ATTRS{idVendor}=="2dc8", ATTRS{idProduct}=="6012", MODE="0660", GROUP="input"
    # Bluetooth
    KERNEL=="hidraw*", KERNELS=="*2DC8:6012*", MODE="0660", GROUP="input"
  '';

  system.autoUpgrade.enable = true;
  system.autoUpgrade.allowReboot = true;

  boot = {
    initrd = {
      systemd.enable = true;
      luks.devices."cryptroot".crypttabExtraOpts = [ "fido2-device=auto" ];
    };
    # X2 Elite SoC/GPU support requires a recent kernel — use our patched
    # linuxPackages_latest that adds the Glymur Yoga Slim 7x board DTS (not
    # yet upstream; see overlays/yoga-kernel.nix).
    kernelPackages = pkgs.linuxPackages_yoga_slim7x;
    kernelParams = [
      # systemd picked the debug UART as the only console on the Yoga Slim 7x
      # (X1E); same SoC-family quirk.
      "console=tty1"
      # If the machine randomly locks up, try adding "pcie_aspm=off"
      # (documented X Elite SSD-ASPM workaround, off by default).
    ];
    blacklistedKernelModules = [
      # Camera ISP driver too buggy on X Elite — kernel crashes. If the X2
      # build lacks this module the blacklist is a harmless no-op.
      "qcom_iris"
    ];
  };
  boot.loader = {
    # rEFInd: ARM-native (refind_aa64), auto-detects kernels + LUKS/FIDO2
    # cleanly on NixOS-only UEFI installs. Grub's os-prober/cryptodisk
    # complexity is unnecessary here (no dual-boot).
    refind = {
      enable = true;
      # rEFInd auto-finds the ESP; only set efiDevice if it can't detect it.
      # efiDevice = "nodev";
    };
    efi = {
      canTouchEfiVariables = true;
      #efiSysMountPoint = "/boot/efi";
    };
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.extra-substituters = [ "https://pi.cachix.org" ];
  nix.settings.extra-trusted-public-keys = [
    "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
  ];

  networking.hostName = "yogabook"; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;
    autorun = false;
    displayManager.startx = {
      enable = true;
    };
    windowManager.awesome = {
      enable = true;
      luaModules = with pkgs.luaPackages; [
        luarocks
        luadbi-mysql
        vicious
      ];
    };
    # OLED hiDPI: uncomment and tune once you see the rendering (the 2880x1800
    # panel wants ~160+; the 1920x1200 base panel is fine at 120 like the laptop).
    # dpi = 160;
  };

  # Qualcomm (Adreno/Hexagon) firmware is non-free; required for GPU.
  hardware.enableRedistributableFirmware = true;

  services = {
    displayManager.defaultSession = "none+awesome";
    picom = {
      enable = true;
      backend = "glx";
      shadow = true;
      vSync = true;
    };

    logind = {
      settings.Login = {
        HandleLidSwitch = "suspend";
        HandleLidSwitchExternalPower = "ignore";
        HandleLidSwitchDocked = "ignore";
        HandlePowerKey = "suspend";
        HandlePowerKeyLongPress = "poweroff";
      };
    };
  };

  programs.zsh.enable = true;

  # Configure keymap in X11
  services.xserver.xkb.layout = "us";

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.jane = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "input"
      "networkmanager"
      "audio"
    ];
    shell = pkgs.zsh;
  };

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
    appimage-run
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  systemd.sleep.settings.Sleep = {
    SuspendState = "mem";
  };

  system.stateVersion = "25.05"; # Did you read the comment?
}
