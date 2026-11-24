# Replace CHANGE_ME_* UUIDs with real partition UUIDs (`blkid`) during install.
#
# Layout (mirrors jane-pc):
#   /dev/nvme0n1p1  1024MiB FAT32 ESP mounted at /boot (1GiB: two 7.4-rc3
#                   generations with copyKernels + initrd + Mahua DTB)
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

  # Load I2C HID keyboard/touchpad + the full msm/eDP/USB-C HPD bridge stack
  # in initrd so msm_dpu binds and renders the LUKS/FIDO2 prompt on the OLED
  # panel before switch-root (af54000/af5c000 DP controllers defer indefinitely
  # without pmic_glink + pmic_glink_altmode creating aux_hpd_bridge).
  boot.initrd.kernelModules = [
    "i2c_hid_of"
    "hid_multitouch"
    "mdt_loader"
    "phy_qcom_qmp_combo"
    "pmic_glink"
    "pmic_glink_altmode"
    "aux_bridge"
    "aux_hpd_bridge"
    "drm_dp_aux_bus"
    "drm_display_helper"
    "panel_samsung_atna33xc20"
    "msm"
  ];

  boot.initrd.systemd.contents = {
    "/var/lib/mahua-firmware/qcom/gen80100_sqe.fw".source = ./firmware/gen80100_sqe.fw;
    "/var/lib/mahua-firmware/qcom/gen80100_gmu.bin".source = ./firmware/gen80100_gmu.bin;
    "/var/lib/mahua-firmware/qcom/gen80100_aqe.fw".source = ./firmware/gen80100_aqe.fw;
  };

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

  boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/0aef5b9f-ad18-41fc-a1f5-2f5aa2afcbba";

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
