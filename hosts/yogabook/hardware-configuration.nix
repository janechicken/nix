# Replace CHANGE_ME_* UUIDs with real partition UUIDs (`blkid`) during install.
#
# Layout (mirrors jane-pc):
#   /dev/nvme0n1p1  1024MiB FAT32 ESP mounted at /boot (1GiB: GRUB keeps 8
#                   generations; `copyKernels` deduplicates by store path so the
#                   shared 7.4-rc3 `Image` + initrd are stored once)
#   /dev/nvme0n1p2  LUKS2 ("cryptroot", FIDO2 + passphrase) -> Btrfs with @ and @home subvolumes
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "nvme"
    "usb_storage"
    "sd_mod"
    "usbhid"
    "i2c_hid_of"
    "i2c_hid_of_elan"
    "hid_multitouch"
    # NOT the display stack: `usb_0_qmpphy` (`qcom,glymur-qmp-usb3-dp-phy`) is
    # driven only by `phy-qcom-qmp-combo` (=m), and `dwc3_core_get_phy()` does
    # `devm_phy_get(dev, "usb3-phy")`, which returns -EPROBE_DEFER when the PHY
    # provider is unbound. Without it every DWC3 controller (incl. `a600000.usb`,
    # the YubiKey port) would never probe in stage 1 and FIDO2 unlock would fail.
    "phy_qcom_qmp_combo"
  ];

  # Stage 1 carries only what LUKS/FIDO2 + the internal keyboard need. The whole
  # display stack lives in stage 2 (`boot.kernelModules` below).
  #
  # Proven root cause of the black LUKS screen ("Option A"): with `msm` +
  # `panel_samsung_atna33xc20` in initrd, `atna33xc20_probe()` runtime-autosuspends
  # 2 s after probe (it drops `VREG_EDP_3P3` and puts the TCON into DPCD D3)
  # because `msm_dpu` defers on `af54000`/`af5c000` — those USB-C DP controllers
  # never appear in stage 1 since `pmic_glink_altmode` is stage-2 only. The
  # autosuspended panel then kills the UEFI GOP OLED scanout that `simpledrm`
  # (`CONFIG_DRM_SIMPLEDRM=y`, built into the kernel Image) was driving, so the
  # LUKS/FIDO2 prompt renders to a panel nobody scans out.
  #
  # Keeping the display stack out of initrd leaves `simpledrm` as the only DRM
  # device in stage 1, so the UEFI-lit panel keeps showing the LUKS prompt, and
  # stage 2 still gets the normal `msm_dpu` bring-up after switch-root (and after
  # ADSP/`remoteproc1`). Fallback if stage 2 still loses the panel: mark
  # `VREG_EDP_3P3` `regulator-always-on` in the board DTS ("Option A'").
  boot.initrd.kernelModules = [
    "i2c_hid_of"
    "hid_multitouch"
  ];

  # Display stack, stage 2 only. No initrd firmware staging is needed anymore:
  # `msm` now loads after switch-root, where the declarative `mahua-firmware`
  # derivation already ships `qcom/gen80100_{sqe,gmu,aqe}` in /lib/firmware
  # (see `configuration.nix`). `phy_qcom_qmp_combo` also stays in stage 1 via
  # `availableKernelModules` above, but only for its USB3 PHY half.
  boot.kernelModules = [
    "mdt_loader"
    "phy_qcom_qmp_combo"
    "aux_bridge"
    "aux_hpd_bridge"
    "drm_dp_aux_bus"
    "drm_display_helper"
    "panel_samsung_atna33xc20"
    "msm"
  ];

  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/dbec1f7e-9c0b-4b51-bf02-dc7ac0f3602d";
    fsType = "btrfs";
    options = [
      "subvol=@"
      "compress=zstd"
      "noatime"
    ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/dbec1f7e-9c0b-4b51-bf02-dc7ac0f3602d";
    fsType = "btrfs";
    options = [
      "subvol=@home"
      "compress=zstd"
      "noatime"
    ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/17B8-1B5C";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  boot.initrd.luks.devices."cryptroot".device =
    "/dev/disk/by-uuid/0aef5b9f-ad18-41fc-a1f5-2f5aa2afcbba";

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
