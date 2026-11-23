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

  # Load only the I2C HID keyboard/touchpad in initrd so the LUKS/FIDO2 prompt
  # works on the laptop screen via simpledrm/efifb.
  boot.initrd.kernelModules = [
    "i2c_hid_of"
    "hid_multitouch"
  ];

  # `msm` (Adreno) and the OLED panel driver load in stage 2 instead: their
  # firmware lives in /var/lib/mahua-firmware, which is not mounted inside initrd.
  boot.kernelModules = [
    "msm"
    "panel_samsung_atna33xc20"
  ];

  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/CHANGE_ME_BTRFS_UUID";
    fsType = "btrfs";
    options = [
      "subvol=@"
      "compress=zstd"
      "noatime"
    ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/CHANGE_ME_BTRFS_UUID";
    fsType = "btrfs";
    options = [
      "subvol=@home"
      "compress=zstd"
      "noatime"
    ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/CHANGE_ME_EFI_UUID";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/CHANGE_ME_LUKS_UUID";

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
