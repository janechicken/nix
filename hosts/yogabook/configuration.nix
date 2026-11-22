# Lenovo Yoga Slim 7 14Q8Y11 (83QR) — Snapdragon X2 Plus (Mahua / X2P-42-100), aarch64.
#
# Hardware verified on Linux 7.4.0-rc3 (pkgs.linuxPackages_mahua):
#   - 6-core Snapdragon X2 Plus @ EL2 with KVM VHE
#   - Adreno X2-45 GPU (915 MHz) + Samsung ATNA40CT03-0 14.0" 1920x1200@60Hz AMOLED eDP
#   - WCN7850 WiFi 7 (wlan0) + Bluetooth (hci0)
#   - QTEC0001 keyboard (i2c0), ELAN06FA touchpad (i2c0), GXPT7936 touchscreen (i2c8)
#   - Samsung NVMe on PCIe5, ADSP/CDSP/SOCCP remoteprocs, QTEE, Battery, 3x USB-C UCSI
#
# Proprietary Lenovo 83QR firmware blobs (ADSP/CDSP/GPU/WCN7850 BT NV) are loaded
# from /var/lib/mahua-firmware via firmware_class.path so they stay out of the public repo.

{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
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
    ../../modules/virtualisation.nix
    ../../modules/xdg-portal.nix
    ../../modules/lock.nix
    ../../modules/joyshockmapper.nix
    inputs.sops-nix.nixosModules.sops
    ../../secrets/sops-nix.nix
  ];

  services.joyshockmapper.enable = true;

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

  # Hardware Device Tree for Lenovo Yoga Slim 7 14Q8Y11 (Mahua).
  # GRUB passes this via `devicetree` for every NixOS generation.
  hardware.deviceTree = {
    enable = true;
    name = "qcom/mahua-lenovo-yoga-slim7-14q8y11.dtb";
  };

  # Qualcomm redistributable firmware + Lenovo 83QR extracted blobs at /var/lib/mahua-firmware
  hardware.enableRedistributableFirmware = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  hardware.graphics.enable = true;

  boot = {
    initrd = {
      systemd.enable = true;
      luks.devices."cryptroot".crypttabExtraOpts = [ "fido2-device=auto" ];
    };

    kernelPackages = pkgs.linuxPackages_mahua;

    # Hardware-verified Mahua bring-up parameters:
    # - clk/pd/regulator_ignore_unused: keep UEFI-enabled rails/clocks alive during early boot
    # - nokaslr + efi=novamap: required for Qualcomm EL2 UEFI stub on Lenovo 83QR
    # - arm-smmu.disable_bypass=0: preserve UEFI SMMU bypass mappings until drivers attach
    # - initcall_blacklist=scmi_driver_init,qcom_cpucp_mbox_init: avoids Mahua SCMI shmem hang
    # - firmware_class.path: loads Lenovo 83QR extracted firmware before /lib/firmware
    kernelParams = [
      "clk_ignore_unused"
      "pd_ignore_unused"
      "regulator_ignore_unused"
      "nokaslr"
      "efi=novamap"
      "arm-smmu.disable_bypass=0"
      "console=tty0"
      "fbcon=font:TER16x32"
      "initcall_blacklist=scmi_driver_init,qcom_cpucp_mbox_init"
      "firmware_class.path=/var/lib/mahua-firmware"
    ];

    # Ensure qrtr-mhi loads before ath12k_wifi7 so WCN7850 WiFi 7 initializes reliably
    kernelModules = [
      "qrtr_mhi"
      "ath12k_wifi7"
    ];

    blacklistedKernelModules = [
      "qcom_iris"
    ];
  };

  boot.loader = {
    grub = {
      enable = true;
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

  networking.hostName = "yogabook";
  networking.networkmanager.enable = true;

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # X11 + Awesome WM matching Windows 125% scaling (120 DPI on 14" 1920x1200 OLED)
  services.xserver = {
    enable = true;
    autorun = false;
    dpi = 120;
    videoDrivers = [ "modesetting" ];
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
    xkb.layout = "us";
  };

  services = {
    displayManager.defaultSession = "none+awesome";
    libinput.enable = true;
    upower.enable = true;
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

  users.users.jane = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "input"
      "networkmanager"
      "audio"
      "video"
      "libvirtd"
    ];
    shell = pkgs.zsh;
  };

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
    brightnessctl
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  networking.firewall.enable = false;

  systemd.sleep.settings.Sleep = {
    SuspendState = "mem";
  };

  system.stateVersion = "25.05";
}
