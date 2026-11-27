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
    # `phy_qcom_qmp_combo` is needed for **both** halves of the board:
    #   * USB: `usb_0_qmpphy` (`qcom,glymur-qmp-usb3-dp-phy`) is driven only by
    #     `phy-qcom-qmp-combo` (=m), and `dwc3_core_get_phy()` does
    #     `devm_phy_get(dev, "usb3-phy")`, which returns -EPROBE_DEFER when the
    #     PHY provider is unbound. Without it every DWC3 controller (incl.
    #     `a600000.usb`, the YubiKey port) would never probe in stage 1 and
    #     FIDO2 unlock would fail.
    #   * Display: `fd5000.phy` / `fde000.phy` (the `af54000` / `af5c000` DP
    #     controllers' PHYs) are `qcom-qmp-combo-phy` too, and the display
    #     component master (`msm_dpu`) will not bind until they are.
    "phy_qcom_qmp_combo"
  ];

  # Stage 1 carries what LUKS/FIDO2 + the internal keyboard need **plus the real
  # display stack**.
  #
  # Why the display stack has to be in initrd at all: the UEFI GOP scanout is
  # dead once the kernel owns the framebuffer. A GRUB `e`-line boot with
  # `earlycon=efi ignore_loglevel loglevel=8 fbcon=nodefer consoleblank=0` stayed
  # completely black through LUKS, i.e. the kernel was alive and logging while
  # nothing reached the panel. Built-in `simpledrm` (`CONFIG_DRM_SIMPLEDRM=y`)
  # therefore cannot light the ATNA40CT03-0 AMOLED panel in stage 1 -- only `msm`
  # can.
  #
  # This is the hardware-verified `system-10` stage-1 set. `5475991` dropped it,
  # but *not* because the modules failed to bind: `fb0: msmdrmfb` does register in
  # stage 1. What blacked the panel out ~2 s later was
  # `panel-samsung-atna33xc20`'s own runtime autosuspend:
  # `atana33xc20_probe()` arms `pm_runtime_set_autosuspend_delay(dev, 2000)` and
  # drops its last reference with `pm_runtime_put_autosuspend()`, so unless the
  # CRTC modeset lands inside those 2 s the panel runtime-suspends and
  # `atana33xc20_suspend()` powers off `VREG_EDP_3P3` and puts the TCON into DPCD
  # D3. That race is closed by the `mahua-panel-pm` initrd udev rule + unit in
  # `configuration.nix`, which pin `power/autosuspend_delay_ms = -1`.
  #
  # Everything the `ae01000.display-controller` component master waits on is
  # available in stage 1: the DP PHYs (`faac00.phy` = built-in `qcom-edp-phy`,
  # `fd5000.phy`/`fde000.phy` = `phy_qcom_qmp_combo` from
  # `availableKernelModules` above), the `af6c000` aux-bus panel
  # (`panel_samsung_atna33xc20`) and the Adreno GPU (microcode staged below).
  # `pmic_glink`/`pmic_glink_altmode` still stay OUT of initrd on purpose: they
  # are only needed for the two USB-C DP controllers' HPD bridges, and binding
  # `msm_dpu` before ADSP (`remoteproc1`) is up is what black-screened
  # `system-11` after switch-root.
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

  # `msm` has no `MODULE_FIRMWARE()` entries -- `adreno_request_fw()` builds the
  # names at run time -- so `makeModulesClosure`'s `modinfo -F firmware` walk
  # cannot discover the Adreno X2-45 microcode and would leave the GPU component
  # unprobed, i.e. `msm_dpu` never binds. `extraFirmwarePaths` copies them out of
  # `hardware.firmware` (the local `mahua-firmware` derivation in
  # `configuration.nix`) into the initrd at `/lib/firmware/qcom/`, which is the
  # kernel's last-resort `fw_path` entry (the cmdline's
  # `firmware_class.path=/var/lib/mahua-firmware` is tried first and simply
  # misses in stage 1).
  boot.initrd.extraFirmwarePaths = [
    "qcom/gen80100_sqe.fw"
    "qcom/gen80100_gmu.bin"
    "qcom/gen80100_aqe.fw"
  ];

  # The same display stack again for stage 2. Every module above is already
  # loaded by stage 1 and stays loaded across switch-root, so this list is an
  # idempotent no-op; it is kept as the declarative record of what stage 2 needs.
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
