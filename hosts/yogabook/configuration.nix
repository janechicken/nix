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
    ../../modules/tailscale.nix
    ../../modules/virtualisation.nix
    ../../modules/hyprland.nix
    ../../modules/joyshockmapper.nix
    ../../modules/ntsync.nix
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

    # ── Runtime PM on the unused USB controllers (battery life) ────────────
    # dwc3 core takes a pm_runtime_forbid() reference in .probe, so the glue
    # devices never autosuspend by default. Writing power/control="auto" drops
    # that reference (drivers/base/power/runtime.c: pm_runtime_allow()); the
    # glue then idles after its 5 s autosuspend delay and dwc3_qcom_suspend()
    # gates the controller clocks + interconnect paths. Only the four
    # controllers with nothing attached are matched:
    #   a000000.usb  usb4 + usb5                (eUSB2 phy 88e0000, QMP 88e1000)
    #   a200000.usb  usb1                       (eUSB2 phy fa0000)
    #   a400000.usb  usb2 + usb3                (eUSB2 fa1000/fa2000, QMP fa3000/fa5000)
    #   a800000.usb  usb8 + usb9                (eUSB2 fdd000, QMP fde000)
    # a600000.usb is deliberately NOT matched: it hosts the YubiKey (6-1) and
    # is the verified zero-fault s2idle path (`SID=0x1420`).
    ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="dwc3-qcom", KERNEL=="a000000.usb|a200000.usb|a400000.usb|a800000.usb", ATTR{power/control}="auto"

    # Their xHCI children (xhci-hcd.{1,2,3,5}.auto). xhci_plat_probe() also
    # calls pm_runtime_forbid() -- "users should enable runtime pm using
    # power/control in sysfs" -- and the root hubs (usb1/2/3/4/5/8/9) are
    # already autosuspended, so dropping the forbid reference lets the
    # controller idle. `bind` matters because mahua-sleep-quirks rebinds these
    # devices on every resume, which re-runs xhci_plat_probe() and restores
    # power/control="on".
    #
    # The four parents are whitelisted by name on purpose: a negated KERNELS
    # match CANNOT exclude a parent. KERNELS/ATTRS walk the device and every
    # ancestor, and `!=` is true as soon as *any* of them fails to match -- so
    # `KERNELS!="a600000.usb"` was true for xhci-hcd.4.auto itself (its own
    # KERNEL is "xhci-hcd.4.auto"), and udev happily wrote "auto" there:
    #   udevadm test --action=add .../a600000.usb/xhci-hcd.4.auto
    #     -> 99-local.rules: ATTR{power/control}="auto"   (wrong, control=suspended)
    # A positive KERNELS match is only true when the device or one of its
    # parents really carries that name, i.e. exactly the four unused
    # controllers, and never a600000.usb.
    ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="xhci-hcd", KERNEL=="xhci-hcd.*.auto", KERNELS=="a000000.usb|a200000.usb|a400000.usb|a800000.usb", ATTR{power/control}="auto"

    # QMP USB3 PHYs of those four controllers: 88e1000 (a000000),
    # fa3000 + fa5000 (a400000), fde000 (a800000). phy_power_on() holds a
    # runtime-PM reference while a consumer uses the PHY (drivers/phy/phy-core.c),
    # so an in-use PHY can never suspend. The M31 eUSB2 PHYs
    # (88e0000/fa0000/fa1000/fa2000/fdd000) are intentionally absent:
    # qcom-m31eusb2-phy implements no runtime PM at all (power/runtime_enabled
    # reads "disabled", runtime_status "unsupported"), so "auto" is a no-op.
    ACTION=="add|bind", SUBSYSTEM=="platform", KERNEL=="88e1000.phy|fa3000.phy|fa5000.phy|fde000.phy", ATTR{power/control}="auto"

    # NOT covered on purpose:
    # - NVMe 0005:01:00.0: nvme_dev_pm_ops has no .runtime_suspend/.runtime_resume
    #   (drivers/nvme/host/pci.c), and pci_pm_runtime_suspend() falls through to
    #   pci_finish_runtime_suspend() when the driver has no callback, i.e. the
    #   controller would be put into D3hot behind the nvme driver's back. The
    #   SSD's own power management is APST, already active
    #   (nvme_core.default_ps_max_latency_us=100000).
    # - ath12k 0004:01:00.0 / root port 0004:00:00.0: WCN7850 firmware hangs in
    #   MHI M2, which is why mahua-sleep-quirks unbinds it around s2idle.
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
  # No DT overlays: the previous "Option A'" overlay (`regulator-always-on` on
  # `VREG_EDP_3P3`) was dropped. `VREG_EDP_3P3` already carries
  # `regulator-boot-on` + `regulator_ignore_unused`, so the overlay was a
  # Stage-1 no-op (the LUKS prompt stayed black with it live in the booted DT)
  # while `regulator-always-on` additionally blocks the panel 3.3 V rail from
  # powering down in `s2idle`. See hosts/yogabook/BRINGUP.md.
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

    # NixOS emits `loglevel=$consoleLogLevel` in kernelParams (and
    # kernel.printk) from this option; the default is 4. At 4 the benign
    # boot-time `qcom-apm ... 1001021` timeout (KERN_WARNING) is printed on
    # /dev/tty1 right over the console. 3 keeps KERN_ERR and above on the
    # console while every message is still recorded in dmesg/journalctl.
    consoleLogLevel = 3;

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
  # MAC randomization stays off (`wifi.scanRandMacAddress = false`) — that is the
  # setting ath12k timeouts on scans were traced to — while Wi-Fi power save is
  # now on: `wcn7850 hw2.0` declares `.supports_sta_ps = true`
  # (`drivers/net/wireless/ath/ath12k/wifi7/hw.c`), so
  # `ath12k_mac_bss_info_changed()` handles `BSS_CHANGED_PS` via
  # `ath12k_mac_vif_setup_ps()` + the sticky-DTIM WMI param, i.e. the firmware
  # really dozes between DTIMs instead of keeping the RX path hot.
  # NetworkManager emits `wifi.powersave=3` for this. The two knobs are
  # independent; if scans ever time out again, revert this one first.
  networking.networkmanager = {
    enable = true;
    wifi.scanRandMacAddress = false;
    wifi.powersave = true;
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
        # Lid close never sleeps: lock + pause all media + panel DPMS off (the
        # Hyprland `switch:on:` bind in modules/hyprland-home.nix) and hypridle
        # runs lock_cmd on logind's Lock signal.
        HandleLidSwitch = "lock";
        HandleLidSwitchExternalPower = "lock";
        HandleLidSwitchDocked = "ignore";
        # Short press suspends (hypridle's before_sleep_cmd locks first), hold
        # powers off. Ignore user-app sleep inhibitors (e.g. T3 Code's block
        # lock) on explicit physical power-button presses.
        HandlePowerKey = "suspend";
        HandlePowerKeyLongPress = "poweroff";
        PowerKeyIgnoreInhibited = "yes";
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

  # Keep the ADSP `q6apm` graphs alive across pauses, on playback *and* capture.
  # WirePlumber's default 5 s ALSA idle suspend tears a graph down and rebuilds
  # it on every pause/play; `q6apm_dai_prepare()` / `q6apm_graph_close()` ignore
  # APM errors, so a teardown that races a still-open port desyncs host and DSP
  # and wedges audio for the rest of the boot (`q6apm-dai ... -16` then a
  # permanent `qcom-apm ... CMD timeout` + `-110` loop). Both `hw:0,0`
  # (`alsa_output.*`) and `hw:0,1` (`alsa_input.*`) hang off the same card, so
  # both directions must stay out of idle suspend (costs a little idle power on
  # this board only).
  #
  # `session.dont-restore-off-profile` is a *device* property read by
  # `scripts/device/state-profile.lua` in the `find-stored-profile` hook (not a
  # `wireplumber.settings` key): if the persisted `default-profile` state is an
  # `off` profile, WirePlumber keeps the card off on every boot instead of
  # falling back to the default profile.
  services.pipewire.wireplumber.extraConfig."51-mahua-no-alsa-suspend" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          { "node.name" = "~alsa_(output|input).*"; }
        ];
        actions = {
          update-props = {
            "node.pause-on-idle" = false;
            "session.suspend-timeout-seconds" = 0;
          };
        };
      }
      {
        matches = [
          { "device.name" = "~alsa_card.*"; }
        ];
        actions = {
          update-props = {
            "session.dont-restore-off-profile" = true;
          };
        };
      }
    ];
  };

  environment.sessionVariables.ALSA_CONFIG_UCM2 = "${pkgs.alsa-ucm-conf-mahua}/share/alsa/ucm2";
  systemd.user.services = {
    pipewire.environment.ALSA_CONFIG_UCM2 = "${pkgs.alsa-ucm-conf-mahua}/share/alsa/ucm2";
    wireplumber.environment.ALSA_CONFIG_UCM2 = "${pkgs.alsa-ucm-conf-mahua}/share/alsa/ucm2";
  };

  networking.firewall.enable = false;

  # s2idle only: `deep` (PSCI SYSTEM_SUSPEND) is unsupported on Mahua and the
  # cmdline pins mem_sleep_default=s2idle. `SuspendState = "freeze"` forces
  # s2idle unconditionally (systemd 262 removed `SuspendMode=`).
  systemd.sleep.settings.Sleep = {
    SuspendState = "freeze";
  };

  # 16 GiB RAM: zram keeps the laptop responsive without a swap partition
  # (swapDevices = [ ] in hardware-configuration.nix).
  zramSwap.enable = true;

  # schedutil asks the SCMI perf domain for a new OPP at most every
  # `rate_limit_us`; the driver's default is 45 us, i.e. it re-evaluates on
  # essentially every utilization update (~thousands of SCMI mailbox round
  # trips/s under load). 1000 us (1 ms) is still far below the scheduler tick and
  # invisible in latency, while collapsing those requests by >20x.
  #
  # tmpfiles and not a service: `CONFIG_ARM_SCMI_CPUFREQ=y` (checked in
  # /proc/config.gz) means `scmi_cpufreq` is built into the Image, so `policy0`
  # and its `schedutil/` tunables exist before `systemd-tmpfiles-setup` runs —
  # no module-load ordering to wait on. `w-` (write, ignore failure) is what
  # tmpfiles.d(5) documents for API filesystems such as /sys and /proc.
  systemd.tmpfiles.rules = [
    "w- /sys/devices/system/cpu/cpufreq/policy0/schedutil/rate_limit_us - - - - 1000"
  ];

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

  # ── s2idle sleep quirks: unbind before suspend, rebind after resume ─────
  # Two devices break s2idle resume on 83QR:
  #   * ath12k_wifi7_pci (WCN7850 Wi-Fi) hangs in its `suspend_late` MHI
  #     callback, so the driver is unbound before suspend and probed fresh on
  #     resume.
  #   * xhci-hcd keeps its command/event rings armed across the idle entry and
  #     DMAs into freed buffers on resume: `arm-smmu 15000000.iommu` logs
  #     `Unhandled context fault ... SID=0x1420` (0x1420 is `usb@a600000`, the
  #     USB-C DRD port) and the controller comes back dead ("WARNING: Host
  #     System Error", "hub failed to enable device, error -108"), losing every
  #     device on it.
  #
  # `xhci-hcd` is unbound rather than its `dwc3-qcom` parent: `usb_remove_hcd()`
  # halts the controller and frees all of its rings/DMA buffers, while the
  # `dwc3` core, the QMP combo PHYs (`fd5000`/`fde000`/`88e1000`) and the
  # `usb_role_switch` stay up — those PHYs are shared with `pmic_glink_altmode`
  # for USB-C DP altmode/PD, which a `dwc3-qcom` unbind would power down and
  # re-initialise.
  #
  # Devices are discovered at run time: `xhci-hcd.N.auto` instance numbers are
  # probe-order dependent and change between boots.
  systemd.services.mahua-sleep-quirks = {
    description = "Unbind ath12k and USB host controllers around s2idle";
    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
    restartIfChanged = false;
    unitConfig.StopWhenUnneeded = true;
    path = [ pkgs.kmod ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Runs on resume when sleep.target stops, and also if ExecStart fails
      # mid-way so partially unbound devices are still rebound.
      ExecStopPost = pkgs.writeShellScript "mahua-sleep-quirks-resume" ''
        # Intentionally no `set -e`: one failing bind must not skip the
        # remaining USB controllers or strand Wi-Fi.
        # USB first: a still-unbound xHCI is the one that faults the SMMU on
        # the *next* idle entry.
        state=/run/mahua-sleep-quirks

        if [ -f "$state/usb" ]; then
          while read -r name; do
            [ -n "$name" ] || continue
            [ -e "/sys/bus/platform/devices/$name" ] || continue
            # Skip anything the kernel already bound again.
            if [ ! -e "/sys/bus/platform/devices/$name/driver" ]; then
              if ! printf '%s\n' "$name" > /sys/bus/platform/drivers/xhci-hcd/bind; then
                echo "mahua-sleep-quirks: failed to rebind $name" >&2
              fi
            fi
          done < "$state/usb"
        fi

        if [ -f "$state/ath12k" ]; then
          # The driver directory only disappears if the module was unloaded.
          if [ ! -d /sys/bus/pci/drivers/ath12k_wifi7_pci ]; then
            modprobe -a qrtr_mhi ath12k_wifi7 || true
          fi
          while read -r slot; do
            [ -n "$slot" ] || continue
            [ -e "/sys/bus/pci/devices/$slot" ] || continue
            if [ ! -e "/sys/bus/pci/devices/$slot/driver" ]; then
              if ! printf '%s\n' "$slot" > /sys/bus/pci/drivers/ath12k_wifi7_pci/bind; then
                echo "mahua-sleep-quirks: failed to rebind ath12k $slot" >&2
              fi
            fi
          done < "$state/ath12k"
        fi

        rm -rf "$state"
      '';
    };
    script = ''
      state=/run/mahua-sleep-quirks
      rm -rf "$state"
      mkdir -p "$state"
      : > "$state/ath12k"
      : > "$state/usb"

      # WCN7850 Wi-Fi: `ath12k_wifi7_pci` binds PCI slot symlinks such as
      # `0004:01:00.0`; `bind`/`unbind`/`module`/`new_id` are plain files.
      wifi=/sys/bus/pci/drivers/ath12k_wifi7_pci
      for dev in "$wifi"/*; do
        [ -L "$dev" ] || continue
        slot=$(basename "$dev")
        case "$slot" in
          ????\:??\:??.?) ;;
          *) continue ;;
        esac
        printf '%s\n' "$slot" >> "$state/ath12k"
        if ! printf '%s\n' "$slot" > "$wifi/unbind"; then
          echo "mahua-sleep-quirks: failed to unbind ath12k $slot" >&2
        fi
      done

      # USB host controllers: every bound `xhci-hcd.N.auto`.
      usb=/sys/bus/platform/drivers/xhci-hcd
      for dev in "$usb"/xhci-hcd.*.auto; do
        [ -L "$dev" ] || continue
        name=$(basename "$dev")
        printf '%s\n' "$name" >> "$state/usb"
        if ! printf '%s\n' "$name" > "$usb/unbind"; then
          echo "mahua-sleep-quirks: failed to unbind $name" >&2
        fi
      done
    '';
  };

  system.stateVersion = "25.05";
}
