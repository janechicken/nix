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
  ];

  # Stage-1 module set copied verbatim from the hardware-verified `system-10`
  # generation. `msm` + `panel_samsung_atna33xc20` + the DP/USB-C HPD bridge
  # stack must be in initrd so `msm_dpu` binds `fb0: msmdrmfb` before
  # switch-root and the LUKS/FIDO2 prompt renders on the OLED panel (the
  # `af54000`/`af5c000` DP controllers defer indefinitely without
  # `aux_hpd_bridge`).
  #
  # `pmic_glink` / `pmic_glink_altmode` are deliberately kept OUT of initrd.
  # Without `pmic_glink_altmode` the `af54000`/`af5c000` DP controllers defer
  # until stage 2, so stage 1 never gets `msmdrmfb` and the LUKS/FIDO2 prompt
  # stays blind on `simpledrm` (`simpledrmdrmfb` owns `fb0` until `msm_dpu`
  # takes it over after switch-root). Loading them in initrd instead makes
  # `msm_dpu` bind before stage-2 ADSP (`remoteproc1`) is up, which
  # black-screened `system-11` after switch-root; the deferral is kept on
  # purpose, since it reproduces `system-10`'s working stage-2 bring-up.
  boot.initrd.kernelModules = [
    "i2c_hid_of"
    "hid_multitouch"
    "mdt_loader"
    "phy_qcom_qmp_combo"
    "aux_bridge"
    "aux_hpd_bridge"
    "drm_dp_aux_bus"
    "drm_display_helper"
    "panel_samsung_atna33xc20"
    "msm"
  ];

  # `msm` needs the Adreno X2-45 microcode (`gen80100_{sqe,gmu,aqe}`) from
  # initrd, and the kernel cmdline pins `firmware_class.path=/var/lib/mahua-firmware`,
  # so stage the 3 GPU blobs at that path in stage 1 (`system-10` layout).
  # The single copy lives in `hosts/yogabook/firmware/qcom/` (also shipped
  # declaratively to /lib/firmware for stage 2 via hardware.firmware).
  boot.initrd.systemd.contents = {
    "/var/lib/mahua-firmware/qcom/gen80100_sqe.fw".source = ./firmware/qcom/gen80100_sqe.fw;
    "/var/lib/mahua-firmware/qcom/gen80100_gmu.bin".source = ./firmware/qcom/gen80100_gmu.bin;
    "/var/lib/mahua-firmware/qcom/gen80100_aqe.fw".source = ./firmware/qcom/gen80100_aqe.fw;
  };

  # Nothing extra in stage 2: every module above is already loaded in stage 1
  # and stays loaded across switch-root, exactly as in `system-10`.
  boot.kernelModules = [ ];

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
