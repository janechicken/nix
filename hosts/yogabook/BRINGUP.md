# Lenovo Yoga Slim 7 14Q8Y11 (`83QR`) — Mahua Bring-Up Status & Handoff

Host `yogabook` (`aarch64-linux`, Snapdragon X2 Plus / Mahua / `X2P-42-100`).
This file tracks verified hardware state, open issues, and invariants so new sessions on NixOS can pick up without re-discovering past dead ends.

## Kernel & Packaging Architecture

`yogabook` does **not** depend on a separate kernel fork repo. The Nix flake is self-contained:

- `pkgs/linux-mahua/default.nix` — fetches upstream `torvalds/linux` `7.4-rc3` (`7b7fe306dd86b5342d3be8a3f1cbf3bb1ebf280f`) via `fetchurl`, applies 11 patches (`pkgs/linux-mahua/patches/0001`–`0011`), and sets Mahua Kconfig in `structuredExtraConfig`.
- `overlays/mahua-kernel.nix` — exposes `pkgs.linuxPackages_mahua` and overrides `alsa-ucm-conf` with the `Lenovo-Yoga-Slim7-14Q8Y11` UCM2 profile (`2x WSA8845` speakers, `2x VA DMICs`, `2x DP audio`).
- `hosts/yogabook/configuration.nix` — wires `boot.kernelPackages = pkgs.linuxPackages_mahua`, `hardware.deviceTree.name = "qcom/mahua-lenovo-yoga-slim7-14q8y11.dtb"`, Mahua `kernelParams`, and `/var/lib/mahua-firmware`. GRUB does **not** read `hardware.deviceTree.name` (`install-grub.pl` ignores it), so the DTB reaches GRUB via `boot.loader.grub.extraFiles."dtbs/qcom/mahua-lenovo-yoga-slim7-14q8y11.dtb"` plus `extraPerEntryConfig = "devicetree @bootRoot@/dtbs/qcom/…dtb"`.

To iterate on a kernel or DTS fix from NixOS: edit an existing patch or add `0012-*.patch` under `pkgs/linux-mahua/patches/`, register it in `pkgs/linux-mahua/default.nix`, `git add` it (flakes ignore untracked files), and verify with `nh os build .`.

## Verified Working (Live USB, commit `ecc2989`)

- **CPU / Storage:** 6-core Snapdragon X2 Plus @ EL2 (KVM VHE), Samsung PCIe5 NVMe (`/dev/nvme0n1`).
- **Display & Backlight:** Samsung `ATNA40CT03-0` 14.0" 1920×1200@60Hz AMOLED eDP (`panel_samsung_atna33xc20`, eDP v8 PHY patches `0009`–`0010`). `/sys/class/backlight/dp_aux_backlight` dims smoothly across `500`, `1024`, `1500`, `2047` with no blanking (patch `0011`).
- **Audio:** `2x WSA8845` speakers play cleanly over SoundWire + QDSP6 Audioreach (`MultiMedia1` → `WSA_CODEC_DMA_RX_0`, `WSA WSA RX0/1 MUX = AIF1_PB`).
- **Wireless:** WCN7850 Wi-Fi 7 (`ath12k_wifi7` + `qrtr_mhi` + `wireless-regdb`, interface `wlP4p1s0`) verified via `nmcli`; Bluetooth (`hci0`) enumerates.
- **Input:** `QTEC0001` keyboard (`i2c0`), `ELAN06FA` touchpad (`i2c0`), `GXPT7936` touchscreen (`i2c8`).
- **Platform:** ADSP/CDSP/SOCCP remoteprocs, QTEE, battery manager, 3× USB-C UCSI ports (`usb_0`/`usb_1`/`usb_2` + `smb2370_j/k/l` eUSB2 repeaters).

## Open Issue: USB-C Phone Plug-In (`error -71` / `xhci-hcd` Reset Loop)

- **Symptom:** Plugging an Android phone into any of the 3 USB-C ports (`usb_0`, `usb_1`, `usb_2`) fails at multiple USB2 transfer stages (`device descriptor read/64`, `SET_ADDRESS`, `config descriptor`, `set config #1`) with `error -71` (`EPROTO`), followed by `xhci-hcd` bus deregistration/re-registration loops.
- **Already ruled out:** Building `CONFIG_PHY_QCOM_M31_EUSB=y` in-kernel (tested in `ecc2989`) did **not** resolve the issue.
- **First diagnostic step on installed NixOS:** Separate `ucsi_glink` DRP role-flapping from `smb2370` eUSB2 HS eye-diagram signal tuning:
  ```bash
  # Capture Type-C role state + kernel log while plugging the phone in:
  for p in /sys/class/typec/port*; do
    echo "=== $p ==="
    grep . "$p"/{data_role,power_role,power_operation_mode,usb_typec_revision} 2>/dev/null
  done
  dmesg -T | tail -n 80
  ```
  - Also test a passive USB-C→A adapter / hub or a non-DRP USB2 device on the same port.
  - If non-DRP devices work cleanly while direct C-to-C phone fails: focus on `ucsi_glink` / `pmic_glink_altmode` DRP role switching.
  - If USB2 HS transfers fail with `-71` across devices: inspect `smb2370_j_e2_eusb2_repeater`, `smb2370_k_e2_eusb2_repeater`, and `smb2370_l_e2_eusb2_repeater` in `pkgs/linux-mahua/patches/0008-arm64-dts-qcom-mahua-lenovo-yoga-slim7-14q8y11.patch` and test `qcom,tune-usb2-amplitude` / `qcom,tune-usb2-preem` tuning values.

## Post-Install Verification Checklist

Items not yet exercised on the Live USB to verify once booted into installed NixOS:

- [ ] Adreno X2-45 GPU acceleration under Mesa + Awesome WM (`glxinfo -B`, `vulkaninfo`)
- [ ] PipeWire / WirePlumber automatic speaker + internal DMIC (`VA_CODEC_DMA_TX_0`) + DP audio routing via the `alsa-ucm-conf` overlay
- [ ] Bluetooth audio & HID pairing
- [ ] External USB-C DisplayPort Alt Mode monitor output
- [ ] USB-C PD charging and battery percentage / wattage reporting
- [ ] Suspend/resume (`s2idle`) and lid switch behavior
- [ ] Optional future work: re-test `qcom_iris` (video decode) and `qcom_camss` (camera), currently blacklisted for coldplug hangs

## Critical Invariants & Past Dead Ends (Do Not Regress)

1. **`ATNA40CT03-0` OLED Backlight (Patch `0011`):**
   - The Samsung `ATNA40CT03-0` TCON blanks permanently if `drm_edp_backlight_enable()` rewrites `DPCD 0x721` (`DP_EDP_BACKLIGHT_MODE_SET_REGISTER`) when its value already matches, or if `current_level == 0` is left at zero.
   - Keep `0011-drm-dp-skip-redundant-backlight-mode-write.patch` and `BACKLIGHT_CLASS_DEVICE = yes`.
2. **In-Kernel `QCOM_PD_MAPPER = yes`:**
   - Must stay built-in (`=y`, not `=m`) so ADSP `audio_pd` service discovery completes reliably for QDSP6 audio.
3. **WSA Macro Audio Routing (`-5 EIO` trap):**
   - `WSA AIF1 PB` (`WSA_CODEC_DMA_RX_0`) is gated by `WSA WSA RX0 MUX` and `WSA WSA RX1 MUX` (both default to `ZERO`). If those aren't set to `AIF1_PB`, playback silently times out after ~1.15s with `-5 (EIO)` and zero `dmesg` errors.
   - `overlays/mahua-kernel.nix` handles this automatically via `Wsa1SpeakerEnableSeq.conf`.
4. **Firmware Search Path (`/var/lib/mahua-firmware`):**
   - The 25 extracted Lenovo 83QR blobs (ADSP/CDSP/GPU/WCN7850 BT NV + `Lenovo-Yoga-Slim7-14Q8Y11-tplg.bin`) stay out of this public repo and live in `/var/lib/mahua-firmware`.
   - NixOS's `udevd` activation script overwrites `/sys/module/firmware_class/parameters/path`; `system.activationScripts.mahuaFirmware` in `hosts/yogabook/configuration.nix` restores `/var/lib/mahua-firmware` after `udevd` and symlinks `/lib/firmware` to `$systemConfig/firmware` as fallback.
5. **Mandatory Boot `kernelParams`:**
   - `nokaslr` + `efi=novamap`: required for Qualcomm EL2 UEFI stub.
   - `arm-smmu.disable_bypass=0` + `clk_ignore_unused` + `pd_ignore_unused` + `regulator_ignore_unused`: preserve UEFI-initialized rails/clocks/SMMU mappings during early boot.
   - `initcall_blacklist=scmi_driver_init,qcom_cpucp_mbox_init`: prevents Mahua SCMI shmem boot hang.
   - `modprobe.blacklist=qcom_iris,qcom_camss`: prevents video/camera coldplug hangs.
