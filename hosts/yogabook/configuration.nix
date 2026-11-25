# Lenovo Yoga Slim 7 14Q8Y11 (83QR) — Snapdragon X2 Plus (Mahua / X2P-42-100), aarch64.
#
# Hardware verified on Linux 7.4.0-rc3 (pkgs.linuxPackages_mahua):
#   - 6-core Snapdragon X2 Plus @ EL2 with KVM VHE
#   - Adreno X2-45 GPU (915 MHz) + Samsung ATNA40CT03-0 14.0" 1920x1200@60Hz AMOLED eDP
#   - WCN7850 WiFi 7 (wlan0) + Bluetooth (hci0)
#   - QTEC0001 keyboard (i2c0), ELAN06FA touchpad (i2c0), GXPT7936 touchscreen (i2c8)
#   - Samsung NVMe on PCIe5, ADSP/CDSP/SOCCP remoteprocs, QTEE, Battery, 3x USB-C UCSI
#
# Lenovo 83QR firmware blobs (ADSP/CDSP/GPU/WCN7850 BT NV) are vendored in
# hosts/yogabook/firmware/ and wired declaratively through hardware.firmware, so a
# fresh install has every blob in /lib/firmware. /var/lib/mahua-firmware is kept as
# an optional override path for testing new blobs without a rebuild.

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
    ../../modules/hyprland.nix
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

    # ── Suspend (s2idle) wakeup sources (Lenovo 83QR / Kalambo) ────────────
    # Keep: PMIC pwrkey, gpio-keys (lid open), keyboard 0-003a,
    #       qcom-battmgr-ac and qcom-battmgr-usb (charger insertion).

    # PCIe root ports (0004:00:00.0 WCN7850 Wi-Fi, 0005:00:00.0 NVMe):
    # qcom-pcie asserts PERST and powers down the PHY in .suspend_noirq, so
    # WAKE#/CLKREQ# assertions only cause immediate spurious resumes.
    ACTION=="add|bind", SUBSYSTEM=="pci", DRIVER=="pcieport", ATTR{power/wakeup}="disabled"

    # USB dwc3-qcom controllers carry wakeup-source in glymur.dtsi and can
    # trigger spurious resumes during USB-C link renegotiation.
    ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="dwc3-qcom", ATTR{power/wakeup}="disabled"

    # ADSP / CDSP / SOCCP remoteprocs: APSS stays up in s2idle so SMP2P/GLINK
    # IRQs are delivered without remoteproc wakeup armed.
    ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="qcom_q6v5_pas", ATTR{power/wakeup}="disabled"

    # Touchpad (ELAN06FA on i2c0): prevent palm/bag spurious wakes; lid-open,
    # power button, and keyboard remain enabled wakeup sources.
    ACTION=="add|bind", SUBSYSTEM=="i2c", ATTR{modalias}=="of:Ntouchpad*", ATTR{power/wakeup}="disabled"
  '';

  # Disabled during bring-up: an unattended rebuild would pull nixpkgs' stock
  # kernel, stripping linuxPackages_mahua, and could trigger a multi-hour kernel
  # rebuild on this machine. Upgrade manually.
  system.autoUpgrade.enable = false;
  system.autoUpgrade.allowReboot = false;

  # OBS virtual camera compiles out-of-tree v4l2loopback against Linux 7.4-rc3,
  # which risks aborting nixos-install on a kernel API mismatch.
  programs.obs-studio.enableVirtualCamera = lib.mkForce false;

  # Hardware Device Tree for Lenovo Yoga Slim 7 14Q8Y11 (Mahua).
  # hardware.deviceTree only selects the DTB package; NixOS's install-grub.pl
  # ignores hardware.deviceTree.name entirely, so GRUB gets the DTB through
  # boot.loader.grub.extraFiles + extraPerEntryConfig below.
  hardware.deviceTree = {
    enable = true;
    name = "qcom/mahua-lenovo-yoga-slim7-14q8y11.dtb";
  };

  # Qualcomm redistributable firmware + wireless-regdb (regulatory.db) +
  # Lenovo 83QR blobs vendored in hosts/yogabook/firmware/.
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [
    pkgs.wireless-regdb
    # Local derivation instead of a package: the blobs are git-tracked in this
    # repo (hosts/yogabook/firmware/) and there is nothing to fetch or patch.
    #
    # `compressFirmware = false` is load-bearing, and this package must stay
    # uncompressed in /lib/firmware:
    #   * the kernel's fw_get_filesystem_firmware() tries the plain name first
    #     and only then `"$name.zst"`/`"$name.xz"`, so the uncompressed copies
    #     here win over linux-firmware's `.zst` siblings
    #     (ath12k/WCN7850/hw2.0/*, qca/hmtbtfw20.tlv, qca/hmtnv20.*,
    #     qcom/gen80100_*) without needing hiPrio/buildEnv collisions;
    #   * userspace pd-mapper / tqftpserv open `.jsn`/`.mbn` directly from
    #     /lib/firmware and cannot decompress;
    #   * initrd's makeModulesClosure copies firmware by the plain name from
    #     `modinfo -F firmware`, so a compressed package would look "missing".
    # meta.priority = 1 keeps it ahead of linux-firmware (5) in the buildEnv
    # should a future blob ever share an exact path.
    (pkgs.runCommandLocal "mahua-firmware"
      {
        meta.priority = 1;
        compressFirmware = false;
      }
      ''
        mkdir -p $out/lib/firmware
        cp -r ${./firmware}/. $out/lib/firmware/
      ''
    )
  ];
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  hardware.graphics.enable = true;

  # Mesa 26.3.0 ships no Adreno X2-45 (chip id 0xc144060020) entry, so both
  # freedreno and turnip refuse to probe the GPU and Hyprland's eglInitialize()
  # dies with EGL_NOT_INITIALIZED. Scoped here via hardware.graphics.package on
  # purpose: overriding pkgs.mesa in overlays/ would invalidate
  # cache.nixos.org for every GUI package in the closure.
  hardware.graphics.package = pkgs.callPackage ../../pkgs/mesa-mahua { };

  # NixOS's built-in `udevd` activation snippet overwrites
  # /sys/module/firmware_class/parameters/path with the Nix store firmware dir.
  # The 83QR blobs now ship declaratively in /lib/firmware (hardware.firmware
  # above), so /var/lib/mahua-firmware is only an optional override: keep it on
  # the search path (harmless when empty, the loader falls back to /lib/firmware)
  # so a new Lenovo blob can be dropped in and probed without a rebuild.
  # /lib/firmware is symlinked here because userspace readers (pd-mapper,
  # tqftpserv) open firmware files by absolute path.
  system.activationScripts.mahuaFirmware = lib.stringAfter [ "udevd" ] ''
    mkdir -p /lib /var/lib/mahua-firmware
    if [ -e "$systemConfig/firmware" ]; then
      ln -sfn "$(readlink -f "$systemConfig/firmware")" /lib/firmware
    fi
    if [ -e /sys/module/firmware_class/parameters/path ]; then
      echo -n "/var/lib/mahua-firmware" > /sys/module/firmware_class/parameters/path
    fi
  '';

  boot = {
    initrd = {
      luks.devices."cryptroot".crypttabExtraOpts = [
        "fido2-device=auto"
        "token-timeout=2s"
      ];
    };

    kernelPackages = pkgs.linuxPackages_mahua;

    # Hardware-verified Kalambo / Mahua bring-up parameters:
    # - clk/pd/regulator_ignore_unused: boot-time only; keep UEFI-enabled rails/clocks alive
    # - nokaslr + efi=novamap: required for Qualcomm EL2 UEFI stub on Lenovo 83QR
    # - arm-smmu.disable_bypass=0: preserve UEFI SMMU bypass mappings until drivers attach
    # - mem_sleep_default=s2idle: prevents `echo mem` from entering PSCI SYSTEM_SUSPEND (deep)
    # - modprobe.blacklist=qcom_iris,qcom_camss: prevents video/camss coldplug hangs
    # - firmware_class.path: optional override dir for un-packaged 83QR blobs;
    #   everything vendored in hosts/yogabook/firmware/ is already in /lib/firmware
    kernelParams = [
      "clk_ignore_unused"
      "pd_ignore_unused"
      "regulator_ignore_unused"
      "nokaslr"
      "efi=novamap"
      "arm-smmu.disable_bypass=0"
      "mem_sleep_default=s2idle"
      "console=tty0"
      "console=tty1"
      "fbcon=font:TER16x32"
      "modprobe.blacklist=qcom_iris,qcom_camss"
      "firmware_class.path=/var/lib/mahua-firmware"
    ];

    # Ensure qrtr-mhi loads before ath12k_wifi7 so WCN7850 WiFi 7 initializes reliably
    kernelModules = [
      "qrtr_mhi"
      "ath12k_wifi7"
    ];

    blacklistedKernelModules = [
      "qcom_iris"
      "qcom_camss"
    ];
  };

  boot.loader = {
    grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      copyKernels = true;
      device = "nodev";
      # NixOS's install-grub.pl ignores hardware.deviceTree.name, so explicitly
      # stage the Mahua board DTB onto /boot and emit `devicetree` per entry.
      extraFiles."dtbs/qcom/mahua-lenovo-yoga-slim7-14q8y11.dtb" =
        "${config.hardware.deviceTree.package}/qcom/mahua-lenovo-yoga-slim7-14q8y11.dtb";
      # Must use `($drive1)/...`, NOT `@bootRoot@/...`: install-grub.pl
      # substitutes @bootRoot@ (-> `($drive1)/`) only for the default entry, then
      # emits the submenu generations afterwards, leaving literal `@bootRoot@`
      # in every submenu entry. `$grubBoot` is always the first GrubFs() call
      # (`search --set=drive1 --fs-uuid ...` right above this line), so
      # `($drive1)/dtbs/...` resolves the ESP reliably even when USB drives
      # shift `(hd0)` / `(hd1)`.
      extraPerEntryConfig = "devicetree ($drive1)/dtbs/qcom/mahua-lenovo-yoga-slim7-14q8y11.dtb";
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
      # efi=novamap disables UEFI runtime NVRAM writes on Qualcomm EL2
      canTouchEfiVariables = false;
    };
    # modules/core.nix sets 3 for both hosts; `mkForce` keeps that default on
    # jane-pc while giving yogabook room to fall back through bring-up
    # generations. `copyKernels` deduplicates by kernel/initrd store path, so the
    # shared 70.6 MiB `Image` is stored once and each extra generation costs at
    # most its ~27.1 MiB initrd (8 x 27.1 + 70.6 ~= 287 MiB of the 786 MiB free).
    grub.configurationLimit = lib.mkForce 8;
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
  # WCN7850 (ath12k_wifi7_pci) hangs/times out on scans with MAC randomization or powersave
  networking.networkmanager = {
    enable = true;
    wifi.scanRandMacAddress = false;
    wifi.powersave = false;
  };

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  services = {
    upower = {
      enable = true;
      # 83QR firmware never survives a full battery drain: power off instead of
      # a hibernate attempt (no swap-backed hibernation on this board).
      criticalPowerAction = "PowerOff";
    };
    logind = {
      settings.Login = {
        # Lid close never sleeps: lock + mute + panel DPMS off (the Hyprland
        # `switch:on:` bind in modules/hyprland-home.nix) and hypridle runs
        # lock_cmd on logind's Lock signal.
        HandleLidSwitch = "lock";
        HandleLidSwitchExternalPower = "lock";
        HandleLidSwitchDocked = "ignore";
        # Short press suspends (hypridle's before_sleep_cmd locks first), hold
        # powers off.
        HandlePowerKey = "suspend";
        HandlePowerKeyLongPress = "poweroff";
      };
    };
    openssh.enable = true;
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
    alsa-utils
    dconf
    adwaita-icon-theme
    alsa-lib
    appimage-run
    brightnessctl
    openssh
  ];

  environment.sessionVariables.ALSA_CONFIG_UCM2 = "${pkgs.alsa-ucm-conf-mahua}/share/alsa/ucm2";
  systemd.user.services = {
    pipewire.environment.ALSA_CONFIG_UCM2 = "${pkgs.alsa-ucm-conf-mahua}/share/alsa/ucm2";
    wireplumber.environment.ALSA_CONFIG_UCM2 = "${pkgs.alsa-ucm-conf-mahua}/share/alsa/ucm2";
  };

  networking.firewall.enable = false;

  # s2idle only: `deep` (PSCI SYSTEM_SUSPEND) is unsupported on Mahua and the
  # cmdline pins mem_sleep_default=s2idle. SuspendMode must agree, otherwise
  # logind writes "deep" into /sys/power/mem_sleep before suspending.
  systemd.sleep.settings.Sleep = {
    SuspendState = "freeze";
    SuspendMode = "s2idle";
  };

  # 16 GiB RAM: zram keeps the laptop responsive without a swap partition
  # (swapDevices = [ ] in hardware-configuration.nix).
  zramSwap.enable = true;

  # power_supply_register_no_ws() emits the udev add uevent before calling
  # device_init_wakeup(), so disabling batt/wls wakeups via udev is racy.
  # Keep qcom-battmgr-ac and qcom-battmgr-usb enabled for charger-plug wake.
  systemd.services.mahua-wakeup-sources = {
    description = "Disable spurious power_supply wakeup sources on Lenovo 83QR";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];
    wants = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for ps in qcom-battmgr-bat qcom-battmgr-wls; do
        f="/sys/class/power_supply/$ps/power/wakeup"
        if [ -w "$f" ]; then
          echo disabled > "$f"
        fi
      done
    '';
  };

  system.stateVersion = "25.05";
}
