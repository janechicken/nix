# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

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
    ../../modules/obs.nix
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
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x2191", ATTR{power/control}="auto"
  '';

  system.autoUpgrade.enable = true;
  system.autoUpgrade.allowReboot = true;

  # Use the systemd-boot EFI boot loader.
  boot = {
    initrd = {
      # kernelModules = [ "i915" ];
      systemd.enable = true;
      luks.devices."crypthome".crypttabExtraOpts = [ "fido2-device=auto" ];
    };
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
      # Force PCIe ASPM for consistent power states
      "pcie_aspm=force"
      # Ensure backlight control works
      "acpi_backlight=vendor"
    ];
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

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.hostName = "jane-laptop"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

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
    videoDrivers = [ "nvidia" ];
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
    dpi = 120;
  };
  environment.sessionVariables = {
  };

  hardware.nvidia = {
    open = true;
    nvidiaSettings = true;
    powerManagement.enable = true;
    modesetting.enable = true;
  };

  hardware.graphics = {
    enable = true;
    # extraPackages = with pkgs; [
    # ];
    enable32Bit = true;
  };
  services = {
    displayManager.defaultSession = "none+awesome";
    picom = {
      enable = true;
      backend = "glx";
      shadow = true;
      vSync = true;
    };

    logind = {
      lidSwitch = "suspend";
      lidSwitchExternalPower = "ignore";
      lidSwitchDocked = "ignore";
      powerKey = "suspend";
      powerKeyLongPress = "poweroff";
    };

    tlp = {
      enable = true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
        CPU_MIN_PERF_ON_BAT = 0;
        CPU_MAX_PERF_ON_BAT = 30;
        CPU_BOOST_ON_AC = 1;
        CPU_BOOST_ON_BAT = 0;
        START_CHARGE_THRESH_BAT0 = 75;
        STOP_CHARGE_THRESH_BAT0 = 80;
        START_CHARGE_THRESH_BAT1 = 75;
        STOP_CHARGE_THRESH_BAT1 = 80;
        RUNTIME_PM_ON_AC = "on";
        RUNTIME_PM_ON_BAT = "auto";
        PCIE_ASPM_ON_BAT = "powersupersave";
        PCIE_ASPM_ON_AC = "performance";
        DEVICES_TO_ENABLE_ON_LAN_DISCONNECT = "wifi wwan";
        DEVICES_TO_DISABLE_ON_LAN_CONNECT = "wifi wwan";
        DEVICES_TO_DISABLE_ON_BAT = "bluetooth wwan";
        WIFI_PWR_ON_BAT = "on";
      };
    };
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
    appimage-run
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # List services that you want to enable:

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

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
  systemd.sleep.settings.Sleep = {
    HibernateMode = "shutdown";
    SuspendState = "mem";
    ResumeDelaySec = 2;
  };

  system.stateVersion = "25.05"; # Did you read the comment?

}
