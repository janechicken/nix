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
    # fd5000.phy (a600000.usb, the YubiKey port) is listed even though its
    # controller is NOT: the PHY alone stays at control=on forever otherwise
    # (it is a QMP combo PHY with real runtime PM), and the phy-core reference
    # rule above means it simply never idles while usb6/usb7 have a consumer.
    ACTION=="add|bind", SUBSYSTEM=="platform", KERNEL=="88e1000.phy|fa3000.phy|fa5000.phy|fd5000.phy|fde000.phy", ATTR{power/control}="auto"

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
  #
  # Overlays: `dt/camera-soc-overlay.dts` adds the SoC-level camera stack
  # (CAMSS, CSIPHY0/1/4, CCI0/1 and their TLMM pins) that upstream glymur.dtsi /
  # mahua.dtsi do not describe. The earlier "Option A'" overlay
  # (`regulator-always-on` on `VREG_EDP_3P3`) stays dropped: `VREG_EDP_3P3`
  # already carries `regulator-boot-on` + `regulator_ignore_unused`, so it was a
  # Stage-1 no-op (the LUKS prompt stayed black with it live in the booted DT)
  # while `regulator-always-on` additionally blocks the panel 3.3 V rail from
  # powering down in `s2idle`. See hosts/yogabook/BRINGUP.md.
  hardware.deviceTree = {
    enable = true;
    name = "qcom/mahua-lenovo-yoga-slim7-14q8y11.dtb";
    overlays = [
      {
        name = "mahua-camera-soc";
        # libfdt applies this overlay to every DTB whose path contains the
        # filter string, and only when the overlay's own `compatible`
        # intersects the base DTB's (see the head of the .dts).
        filter = "mahua-lenovo-yoga-slim7-14q8y11.dtb";
        dtsFile = ./dt/camera-soc-overlay.dts;
      }
    ];
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

      # ── Keep the ATNA40CT03-0 eDP panel powered through stage 1 ──────────
      # Stage 1 loads the real display stack (`msm`) because the UEFI GOP
      # scanout is dead by then and `simpledrm` cannot light the panel (see
      # `hardware-configuration.nix`). `panel-samsung-atna33xc20` then
      # runtime-autosuspends 2 s after probe unless the CRTC modeset wins that
      # race, and `atana33xc20_suspend()` powers off `VREG_EDP_3P3` + puts the
      # TCON into DPCD D3, i.e. a black LUKS prompt.
      #
      # The device is `aux-af6c000.displayport-controller` on the `dp-aux` bus,
      # verified with `udevadm info -a -p /sys/bus/dp-aux/devices/...`:
      #   KERNEL=="aux-af6c000.displayport-controller"
      #   SUBSYSTEM=="dp-aux"  DRIVER=="samsung_atana33xc20"
      # `DRIVER` is the sysfs driver name (`atana33xc20_driver.driver.name`),
      # NOT the module name `panel_samsung_atna33xc20`.
      #
      # The rule is race-free by construction: `device_add()` calls
      # `bus_probe_device()` *before* emitting the `add` uevent, so the driver is
      # always bound when udev evaluates `DRIVER`. `bind` is matched too so a
      # rebind re-applies the values.
      #
      # `power/autosuspend_delay_ms = -1` is the load-bearing write: with
      # `use_autosuspend` set, `update_autosuspend()` (drivers/base/power/
      # runtime.c) bumps the usage count so the device can never runtime-suspend
      # *and* calls `rpm_resume()`, which also rescues a panel that already
      # suspended before udev got here. `power/control = "on"`
      # (`pm_runtime_forbid()`) is the belt-and-braces equivalent.
      #
      # Both pins are released again by `mahua-panel-pm-release` once stage 2
      # owns the panel -- see the comment on that unit.
      services.udev.rules = ''
        ACTION=="add|bind", SUBSYSTEM=="dp-aux", DRIVER=="samsung_atana33xc20", ATTR{power/autosuspend_delay_ms}="-1", ATTR{power/control}="on"
      '';

      # `systemd-udev-settle.service` is an optional upstream unit (it lives in
      # `${systemd}/example/systemd/system/`), so it has to be pulled in
      # explicitly before `mahua-panel-pm` can order itself after it.
      systemd.additionalUpstreamUnits = [ "systemd-udev-settle.service" ];

      # Belt and suspenders for the udev rule above: re-assert the runtime-PM
      # pins once the initrd udev queue has drained, and make sure the DP AUX
      # backlight is never left at 0 (patch `0011` clamps a *zero probed* level
      # to half max because the TCON blanks permanently on a 0 level).
      systemd.services.mahua-panel-pm = {
        description = "Pin the ATNA40CT03-0 eDP panel runtime PM for stage 1";
        wantedBy = [ "initrd.target" ];
        wants = [ "systemd-udev-settle.service" ];
        after = [ "systemd-udev-settle.service" ];
        # Run inside `sysinit.target`, i.e. before the LUKS/FIDO2 prompt is
        # drawn, rather than after it.
        before = [ "sysinit.target" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # No `set -e` games: a missing device must never fail the unit.
          for dev in /sys/bus/dp-aux/devices/*; do
            [ -e "$dev/driver" ] || continue
            [ "$(basename "$(readlink -f "$dev/driver")")" = samsung_atana33xc20 ] || continue
            printf '%s\n' -1 > "$dev/power/autosuspend_delay_ms" || true
            printf '%s\n' on > "$dev/power/control" || true
          done

          for bl in /sys/class/backlight/*; do
            [ -e "$bl/max_brightness" ] || continue
            cur=$(cat "$bl/brightness") || continue
            # Never clobber a level the user (or the firmware) already set.
            [ "$cur" = 0 ] || continue
            max=$(cat "$bl/max_brightness") || continue
            [ "$max" -gt 0 ] || continue
            printf '%s\n' $((max / 2)) > "$bl/brightness" || true
          done
        '';
      };
    };

    kernelPackages = pkgs.linuxPackages_mahua;

    # Hardware-verified Kalambo / Mahua bring-up parameters:
    # - clk/pd/regulator_ignore_unused: boot-time only; keep UEFI-enabled rails/clocks alive
    # - nokaslr + efi=novamap: required for Qualcomm EL2 UEFI stub on Lenovo 83QR
    # - arm-smmu.disable_bypass=0: preserve UEFI SMMU bypass mappings until drivers attach
    # - mem_sleep_default=s2idle: prevents `echo mem` from entering PSCI SYSTEM_SUSPEND (deep)
    # - modprobe.blacklist=qcom_iris: prevents video/iris coldplug hangs. qcom_camss is
    #   no longer blacklisted: the SoC-level camera nodes now come from
    #   dt/camera-soc-overlay.dts, and the driver's own probe path is safe without a
    #   sensor (no "top" reg -> no register access in camss_read_version(), and
    #   camss_parse_ports() skips endpoints whose PHY has no sensor attached).
    # - firmware_class.path: optional override dir for un-packaged 83QR blobs;
    #   everything vendored in hosts/yogabook/firmware/ is already in /lib/firmware
    # - fw_devlink.sync_state=timeout: `fw_devlink.sync_state()` at the end of
    #   driver_init() walks every consumer link, and `1dfa000.crypto` never
    #   probes, so the wait used to stall there and the last sync_state()
    #   consumers never ran: `icc_sync_state()` never voted, leaving the DDR /
    #   LLCC / NoC interconnect BCMs floored at INT_MAX bandwidth (a permanent
    #   power cost on this board). `timeout` gives up instead of blocking
    #   on that link forever, so the remaining sync_state() callbacks run.
    # - msm.psr_enabled=1 is deliberately NOT here: eDP Panel Self-Refresh on
    #   this panel (ATNA40CT03-0) makes the screen flash on/off continuously,
    #   even on a text console. `drm_self_refresh_helper_entry_work` enters
    #   self-refresh (`driver disabled vblank in self-refresh`) and the exit
    #   path then hits `WARNING: drm_atomic_helper.c:1302 at
    #   drm_atomic_helper_commit_crtc_disable`; the panel blanks and relights
    #   on every cycle. Must stay disabled -- do not re-add it (see BRINGUP.md).
    # - pcie_aspm.policy=powersupersave: push L0s as well as L1/L1SS on both
    #   links. `qcom_pcie_clear_aspm_l0s()` clears the L0s capability on the
    #   root ports, so this mainly documents the intent; it is harmless when the
    #   endpoint has no L0s and is reverted by deleting one word here.
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
      "modprobe.blacklist=qcom_iris"
      "firmware_class.path=/var/lib/mahua-firmware"
      "fw_devlink.sync_state=timeout"
      "pcie_aspm.policy=powersupersave"
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
      # EDK2 UEFI Shell, purely as an ACPI-table dumping tool (see the menuentry
      # below). Nothing boots through it; it is a 1.1 MiB .efi on the ESP.
      extraFiles."EFI/shell/shell.efi" = "${pkgs.edk2-uefi-shell}/shell.efi";
      # Must use `($drive1)/...`, NOT `@bootRoot@/...`: install-grub.pl
      # substitutes @bootRoot@ (-> `($drive1)/`) only for the default entry, then
      # emits the submenu generations afterwards, leaving literal `@bootRoot@`
      # in every submenu entry. `$grubBoot` is always the first GrubFs() call
      # (`search --set=drive1 --fs-uuid ...` right above this line), so
      # `($drive1)/dtbs/...` resolves the ESP reliably even when USB drives
      # shift `(hd0)` / `(hd1)`.
      extraPerEntryConfig = "devicetree ($drive1)/dtbs/qcom/mahua-lenovo-yoga-slim7-14q8y11.dtb";
      # Why a UEFI Shell entry: with `hardware.deviceTree.enable` the kernel
      # boots via DT, so the firmware ACPI tables are never consumed and
      # /sys/firmware/acpi/tables stays empty -- they cannot be read from Linux.
      # Scanning low memory for the RSDP from userspace is blocked too, see this
      # kernel's config: CONFIG_STRICT_DEVMEM=y + CONFIG_IO_STRICT_DEVMEM=y and
      # `# CONFIG_PROC_KCORE is not set`. The UEFI Shell still has the firmware's
      # own ACPI table services, so
      #   acpiview -s DSDT -d
      #   acpiview -s SSDT -d
      # dumps the raw tables to the shell's current directory (`-d` writes
      # DSDT.dat / SSDT*.dat there; the ESP is fs0: -- confirm with `map`, `fs0:`
      # if needed), which is /boot from Linux. No USB stick, no Windows, ~15 s.
      extraEntries = ''
        menuentry "UEFI Shell (ACPIVIEW table dump)" {
            chainloader ($drive1)/EFI/shell/shell.efi
        }
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

  # WirePlumber ALSA policy for the ADSP `q6apm` card (`hw:0,0` playback +
  # `hw:0,1` capture on the same card).
  #
  # Idle suspend is deliberately LEFT ON (PipeWire's default 5 s). An earlier
  # generation disabled it (`node.pause-on-idle = false` +
  # `session.suspend-timeout-seconds = 0`) to avoid `q6apm` graph teardown churn
  # (H1 in BRINGUP.md), but a live A/B test showed that costs ~0.7-1.1 W of idle
  # ADSP power: with the graph kept hot the DSP burns ADSP IRQs continuously,
  # while letting the card suspend after 5 s of silence cut those IRQs by 98.7%
  # with zero `q6apm-dai ... -16` / `qcom-apm ... CMD timeout` / `-110` events
  # under the dynamic quantum (`92-dynamic-quantum`, default 1024 in
  # modules/audio.nix). If the `-16` -> `-110` wedge ever comes back on
  # pause/resume, re-adding the two props is the one-line mitigation.
  #
  # `session.dont-restore-off-profile` is a *device* property read by
  # `scripts/device/state-profile.lua` in the `find-stored-profile` hook (not a
  # `wireplumber.settings` key): if the persisted `default-profile` state is an
  # `off` profile, WirePlumber keeps the card off on every boot instead of
  # falling back to the default profile (this bit the internal DMICs once and
  # must stay).
  services.pipewire.wireplumber.extraConfig."51-mahua-audio" = {
    "monitor.alsa.rules" = [
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

  # ── Release the stage-1 panel runtime-PM pin ─────────────────────────
  # `mahua-panel-pm` pins `power/autosuspend_delay_ms = -1` (+ `power/control =
  # "on"`) so the panel cannot autosuspend while stage 1 owns the console. That
  # pin MUST be dropped once stage 2 runs the real display stack, because
  # `atana33xc20_unprepare()` deliberately relies on
  # `pm_runtime_put_sync_suspend()` actually suspending:
  #   * `atana33xc20_disable()` lowers EL_ON3 and sets `el3_was_on = true`;
  #   * only `atana33xc20_suspend()` clears it (after powering off
  #     `VREG_EDP_3P3`);
  #   * `atana33xc20_enable()` does `WARN_ON(p->el3_was_on)` and returns `-EIO`,
  #     and the driver's own comment is "Once EL_ON3 drops we absolutely need a
  #     power cycle before the next enable or the backlight will never come on
  #     again".
  # With the pin still in place the usage count never reaches 0, so the first
  # DPMS off/on cycle (hypridle screen blank, lid close, VT switch) would leave
  # the OLED dark until reboot. Restore exactly the values
  # `atana33xc20_probe()` sets, as early in stage 2 as the device is guaranteed
  # to exist (it was created in stage 1 and survives switch-root).
  systemd.services.mahua-panel-pm-release = {
    description = "Release the stage-1 ATNA40CT03-0 panel runtime-PM pin";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for dev in /sys/bus/dp-aux/devices/*; do
        [ -e "$dev/driver" ] || continue
        [ "$(basename "$(readlink -f "$dev/driver")")" = samsung_atana33xc20 ] || continue
        printf '%s\n' 2000 > "$dev/power/autosuspend_delay_ms" || true
        printf '%s\n' auto > "$dev/power/control" || true
      done
    '';
  };

  system.stateVersion = "25.05";
}
