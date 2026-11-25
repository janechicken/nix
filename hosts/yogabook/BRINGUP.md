# Lenovo Yoga Slim 7 14Q8Y11 (`83QR`) — Kalambo / Mahua Bring-Up Status & Handoff

Host `yogabook` (`aarch64-linux`, Snapdragon X2 Plus `X2P-42-100` — upstream codename **Kalambo**, 6-core Cluster 1 `cpu6..cpu11` derivative of Mahua/Glymur).
This file tracks verified hardware state, applied fixes, post-reboot checks, and critical invariants.

## Kernel & Packaging Architecture

`yogabook` does **not** depend on a separate kernel fork repo. The Nix flake is self-contained:

- `pkgs/linux-mahua/default.nix` — fetches upstream `torvalds/linux` `7.4-rc3` (`7b7fe306dd86b5342d3be8a3f1cbf3bb1ebf280f`) via `fetchurl`, applies 14 patches (`pkgs/linux-mahua/patches/0001`–`0014`), and pins Kalambo/Mahua Kconfig in `structuredExtraConfig` (including `ARM_SCMI_PROTOCOL=y`, `ARM_SCMI_CPUFREQ=y`, `QCOM_CPUCP_MBOX=y`, `QCOM_PD_MAPPER=y`).
- `pkgs/mesa-mahua/` — scoped Mesa package adding Adreno X2-45 (`0xc144060020`, 2 slices, 10.5 MiB GMEM) support, wired via `hardware.graphics.package` (never override `pkgs.mesa` globally in `overlays/`, which breaks `cache.nixos.org` for all GUI packages).
- `overlays/mahua-kernel.nix` — exposes `pkgs.linuxPackages_mahua` and `pkgs.alsa-ucm-conf-mahua` (never override global `alsa-ucm-conf`!) with the `Lenovo-Yoga-Slim7-14Q8Y11` UCM2 profile (`2x WSA8845` speakers, `2x VA DMICs` with `CaptureChannels 2`, `2x DP audio` priority `300`) plus the exact `LENOVO-83QR-YogaSlim714Q8Y11-LNVNB161216.conf` CardLongName symlink required by ALSA UCM2 / PipeWire.
- `hosts/yogabook/hardware-configuration.nix` — restores the hardware-verified `system-10` stage-1 set in `boot.initrd.kernelModules` (`i2c_hid_of`, `hid_multitouch`, `mdt_loader`, `phy_qcom_qmp_combo`, `aux_bridge`, `aux_hpd_bridge`, `drm_dp_aux_bus`, `drm_display_helper`, `panel_samsung_atna33xc20`, `msm`) so `msm_dpu` binds `fb0: msmdrmfb` and renders the LUKS/FIDO2 prompt before switch-root. `boot.initrd.systemd.contents` stages the 3 Adreno `gen80100_{sqe,gmu,aqe}` blobs (single copy: `hosts/yogabook/firmware/qcom/`) at `/var/lib/mahua-firmware/qcom/` (the `firmware_class.path` set by the kernel cmdline). `boot.kernelModules = [ ]` — every module is already loaded in stage 1. `pmic_glink`/`pmic_glink_altmode` stay out of initrd on purpose: they make `msm_dpu` bind before stage-2 ADSP (`remoteproc1`), which black-screened `system-11` after switch-root.
- `hosts/yogabook/firmware/` — every proprietary Lenovo 83QR blob (23 files: Adreno `qcom/gen80100_*`, ADSP/CDSP `qcom/glymur/LENOVO/83QR/*`, the `Lenovo-Yoga-Slim7-14Q8Y11-tplg.bin` topology, WCN7850 `ath12k/WCN7850/hw2.0/*` and BT NV `qca/hmtnv20.*` + `qca/hmtbtfw20.tlv`) is **git-tracked and wired declaratively**: `configuration.nix` builds a local `runCommandLocal "mahua-firmware"` (with `compressFirmware = false`, `meta.priority = 1`) and adds it to `hardware.firmware`, so a fresh install has everything in `/lib/firmware` with no manual copying. Uncompressed is required: the kernel tries the plain name before `"$name.zst"` (so these win over `linux-firmware`'s `.zst` siblings without `buildEnv` collisions), userspace `pd-mapper`/`tqftpserv` open `.jsn`/`.mbn` directly, and initrd's `makeModulesClosure` copies by plain name. `regulatory.db`/`regulatory.db.p7s` are *not* vendored — `hardware.wirelessRegulatoryDatabase` (implied by `enableRedistributableFirmware`) ships `pkgs.wireless-regdb`.
- `hosts/yogabook/configuration.nix` — wires `boot.kernelPackages = pkgs.linuxPackages_mahua`, `hardware.deviceTree.name = "qcom/mahua-lenovo-yoga-slim7-14q8y11.dtb"`, Kalambo `kernelParams`, the `mahua-firmware` derivation, `s2idle` wakeup rules, `mahua-wakeup-sources`, `zramSwap.enable`, `upower.criticalPowerAction = "PowerOff"`, and `systemd.sleep.settings.Sleep.{SuspendState,SuspendMode}`. GRUB does **not** read `hardware.deviceTree.name` (`install-grub.pl` ignores it), so the DTB reaches GRUB via `boot.loader.grub.extraFiles` + `extraPerEntryConfig`. `extraPerEntryConfig` uses the absolute ESP path `devicetree /dtbs/qcom/mahua-lenovo-yoga-slim7-14q8y11.dtb`: `install-grub.pl` substitutes `@bootRoot@` only for the default entry (before `addProfile` runs), so every submenu generation entry used to keep a literal `@bootRoot@` and failed to load the DTB. `boot.loader.grub.configurationLimit = lib.mkForce 8` overrides `modules/core.nix`'s `3` (that is why only 3 generations were listed); `copyKernels` deduplicates by store path, so the shared 70.6 MiB `Image` is stored once and 8 generations cost ~287 MiB of the 786 MiB free on the 1022 MiB ESP.

> **Nix Cache Rule of Thumb:** Never override core shared libraries (`alsa-ucm-conf`, `mesa`, `llvm`, etc.) in `overlays/`. Always scope overrides to dedicated package names (`alsa-ucm-conf-mahua`) or NixOS module options (`hardware.graphics.package`).

## Hardware Fixes Implemented (Linux `7.4.0-rc3`, patches `0001`–`0014`)

- **Display, Backlight & LUKS Console:** Samsung `ATNA40CT03-0` 14.0" 1920×1200@60Hz AMOLED eDP (`panel_samsung_atna33xc20`, eDP v8 PHY patches `0009`–`0010`, backlight patch `0011`). Stage 1 loads the full `msm` + eDP + `aux_hpd_bridge` stack (plus the 3 `gen80100_*` GPU blobs) so `msm_dpu` binds `fb0: msmdrmfb` and the LUKS/FIDO2 prompt renders on the OLED panel; `pmic_glink`/`pmic_glink_altmode` stay in stage 2 after ADSP (`remoteproc1`) so the panel does not black-screen after switch-root (`system-10` behaviour).
- **Desktop & GPU:** Hyprland Wayland (`modules/hyprland.nix`, `modules/hyprland-home.nix`) + Adreno X2-45 (`pkgs/mesa-mahua/`) + patch `0013` adding speed-bin `193` (`0xc1`, `915 MHz`, `BIT(4)`) and `opp-supported-hw = <0x1f>` on `310..915 MHz` OPPs.
- **CPU Frequency Scaling (Kalambo SCMI / CPUFreq):** Patch `0012` adds upstream `kalambo.dtsi` (PDP1 mailbox TX at `0x1a980000`, `imem` size `0x380` with `cpu_scp_lpri1` at `@200`, `cpu6..11` reassigned to `<&scmi_perf 0>`, trimmed 19-range `&pdc`). Board DTS (`0008`) includes `kalambo.dtsi` while retaining `"qcom,mahua"` compatible so `7.4-rc3` `qcom_pd_mapper` keeps matching `audio_pd`. Removed `initcall_blacklist=scmi_driver_init,qcom_cpucp_mbox_init`.
- **USB-C UCSI & eUSB2 Repeater:** Replaced `dr_mode = "host"` with `role-switch-default-mode = "host"` on `&usb_0`, `&usb_1`, `&usb_2` in `0008` so DWC3 registers `usb_role_switch` (unblocking `ucsi_glink` `/sys/class/typec/port{0,1,2}` while defaulting to host mode). Added upstream patch `0014` (`a6d71ecf65b3`) disabling `EUSB2_EN_CTL1` on `smb2370` eUSB2 repeater exit to fix SMB power leakage.
- **Audio (PipeWire / ALSA UCM2):** `alsa-ucm-conf-mahua` symlinks `LENOVO-83QR-YogaSlim714Q8Y11-LNVNB161216.conf`, sets `CaptureChannels 2` on internal DMICs, and lowers `HDMI0`/`HDMI1` priority to `300`. (Note: 83QR has no 3.5 mm jack in hardware.)
- **Suspend (`s2idle`) Readiness:** Added `mem_sleep_default=s2idle` (prevents `echo mem` from entering PSCI `SYSTEM_SUSPEND`/`deep`), udev rules disabling spurious wakeups on PCIe root ports (`pcieport`: Wi-Fi `0004:00:00.0` & NVMe `0005:00:00.0`), `dwc3-qcom`, `qcom_q6v5_pas`, and touchpad `ELAN06FA`, plus `systemd.services.mahua-wakeup-sources` for `qcom-battmgr-{bat,wls}` while keeping PMIC `pwrkey`, `gpio-keys` (lid open), `keyboard@3a`, and `qcom-battmgr-{ac,usb}` armed. Both `drm/msm/a6xx` stale RPMh vote fix and `drm/msm/dp` `PUSH_IDLE` fix are already present in `7.4-rc3`.
- **Wireless & Input:** WCN7850 Wi-Fi 7 (`wlP4p1s0`), Bluetooth (`hci0`), `QTEC0001` keyboard (`i2c0`), `ELAN06FA` touchpad (`i2c0`), `GXPT7936` touchscreen (`i2c8`), lid hall sensor (`gpio-keys`, TLMM 92). (Note: 83QR has no fingerprint reader in hardware.)

## Backlog: Blocked Upstream / Missing Firmware (Out of Scope)

- **`qcom_iris` (HW video decode):** Needs post-7.4 Glymur/Mahua Iris driver + DT series, plus `qcom/vpu/vpu36_p4_s7.mbn`, which is **not** in upstream `linux-firmware` (nor in this repo). Nothing to vendor yet: waits on upstream `linux-firmware` gaining the `vpu36` blob *and* post-7.4 kernel Iris support. Keep blacklisted.
- **`qcom_camss` (MIPI RGB + IR webcam / ToF):** No `glymur`/`mahua` CAMSS DT nodes, no CCI/CSI-2 PHY pipeline, and no sensor support in `7.4-rc3`. Keep blacklisted. Sensor IDs and the CAMSS/CCI blobs must come from Lenovo's **Windows 11 ARM recovery image** (Lenovo DDRS — Driver Recovery/Download Service, `83QR` recovery media) or the **Microsoft Update Catalog** (`qccam*8480` packages), and only become usable once post-7.4 kernel CAMSS/CCI support lands. Lenovo's 83QR support page publishes **no** camera, graphics or chipset drivers (BIOS + diagnostics only), so it cannot be used as the source.
- **ADSP SSC sensors:** No mainline Qualcomm SSC sensor hub driver.

## Post-Reboot Verification Checklist

After `nh os switch .` and rebooting into the new generation:

1. **LUKS prompt:** Confirm passphrase prompt renders visibly on the OLED screen before root unlock.
2. **CPUFreq / SCMI:**
   ```bash
   dmesg | grep -iE 'scmi|cpucp|cpufreq'
   grep . /sys/devices/system/cpu/cpufreq/policy0/scaling_{driver,governor,cur_freq,available_frequencies}
   ```
   *(If SCMI ever hangs on boot, pick the previous GRUB generation or append `initcall_blacklist=scmi_driver_init,qcom_cpucp_mbox_init` on the GRUB command line.)*
3. **Adreno X2-45 speed-bin 193:**
   ```bash
   dmesg | grep -iE 'adreno|speed-bin|gmu'   # expect no "missing support for speed-bin: 193"
   cat /sys/class/devfreq/3d00000.gpu/available_frequencies
   ```
4. **USB-C UCSI & USB2 devices:**
   ```bash
   ls -la /sys/class/usb_role/ /sys/class/typec/
   dmesg | grep -iE 'ucsi|typec|eusb2|smb2370'
   ```
   Then plug in a USB-C phone/hub/DP monitor to verify Type-C PD/roles and USB2 enumeration.
5. **PipeWire Audio:**
   ```bash
   wpctl status
   ```
6. **Suspend (`s2idle`) staged test (run as root):**
   ```bash
   cat /sys/power/mem_sleep   # expect: [s2idle] deep
   cat /sys/power/state       # expect: freeze mem
   # pm_test ladder — every rung must come back on its own:
   echo freezer  > /sys/power/pm_test && echo freeze > /sys/power/state && echo none > /sys/power/pm_test
   echo devices  > /sys/power/pm_test && echo freeze > /sys/power/state && echo none > /sys/power/pm_test
   echo platform > /sys/power/pm_test && echo freeze > /sys/power/state && echo none > /sys/power/pm_test
   # If all three rungs pass cleanly, test real s2idle:
   systemctl suspend
   ```
   - **`echo freeze`, never `echo mem`:** `freeze` unconditionally means suspend-to-idle. `mem` means "whatever `/sys/power/mem_sleep` currently selects", so a single stray write of `deep` into `mem_sleep` (older logind `SuspendMode=deep`, a `pm_test` script, a manual test) turns the next `echo mem` into PSCI `SYSTEM_SUSPEND`, which Mahua does not support → silent hang with no wake. `freeze` removes that ambiguity, which is also why `systemd.sleep.settings.Sleep.SuspendMode = "s2idle"` is pinned in `configuration.nix`.
   - **`pm_test` ladder semantics:** `freezer` = tasks frozen only; `devices` = every `.suspend`/`.resume` callback runs and then wakes immediately; `platform` = platform/irqchip `suspend_ops` also run. The first rung that hangs identifies the layer: hang at `devices` → a driver's suspend callback; hang at `platform` → the `domain_ss3` idle domain or `qcom,glymur-pdc` (PDC/TCS wake programming).
   - **`cpuidle.off=1` A/B test:** if `platform` (or real s2idle) hangs, reboot with `cpuidle.off=1` appended in GRUB and repeat. Passing with cpuidle off pins the fault on `domain_ss3`/`qcom,glymur-pdc` idle-state entry rather than a driver callback.
   - **`rtcwake` / timed wake cannot work on this board:** `apps_rsc` reports `CONTROL_TCS 0`, so the RSC cannot arm a TCS/RTC wake timer. `rtcwake -m freeze -s 20` will therefore look like a hang until something else wakes the machine. Only the **physical power key**, **lid open**, and **keyboard** are reliable wake sources — use the power key for the `pm_test` rungs and the real suspend test.

## Critical Invariants & Past Dead Ends (Do Not Regress)

1. **`ATNA40CT03-0` OLED Backlight (Patch `0011`):**
   - The Samsung `ATNA40CT03-0` TCON blanks permanently if `drm_edp_backlight_enable()` rewrites `DPCD 0x721` when its value already matches, or if `current_level == 0`.
   - Keep `0011-drm-dp-skip-redundant-backlight-mode-write.patch` and `BACKLIGHT_CLASS_DEVICE = yes`.
2. **In-Kernel `QCOM_PD_MAPPER = yes` & `"qcom,mahua"` Board Compatible:**
   - `QCOM_PD_MAPPER` must stay built-in (`=y`, not `=m`), and `mahua-lenovo-yoga-slim7-14q8y11.dts` must keep `"qcom,mahua"` in its root `compatible` on `7.4-rc3` (`qcom_pd_mapper.c` matches `"qcom,mahua"`, not `"qcom,kalambo"`) so ADSP `audio_pd` service discovery works.
3. **WSA Macro Audio Routing (`-5 EIO` trap):**
   - `WSA WSA RX0 MUX` and `WSA WSA RX1 MUX` must be set to `AIF1_PB` (`Wsa1SpeakerEnableSeq.conf` in `overlays/mahua-kernel.nix`), otherwise playback times out silently with `-5 (EIO)`.
4. **Firmware (declarative, `/lib/firmware`):**
   - Every Lenovo 83QR blob lives in `hosts/yogabook/firmware/` (git-tracked) and is installed to `/lib/firmware` by `hardware.firmware` via the local `mahua-firmware` derivation (`compressFirmware = false`, `meta.priority = 1`). Nothing has to be copied into `/var/lib/mahua-firmware` on a fresh install.
   - `/var/lib/mahua-firmware` remains on the kernel search path (`firmware_class.path`, restored by `system.activationScripts.mahuaFirmware` after `udevd`, which otherwise overwrites it with the Nix store firmware dir) purely as an **optional override** for testing a new blob without a rebuild; when empty the loader falls back to `/lib/firmware`.
   - Keep the blobs **uncompressed**: the kernel tries the plain name before `"$name.zst"`/`"$name.xz"`, so they shadow `linux-firmware`'s `.zst` siblings (`ath12k/WCN7850/hw2.0/*`, `qca/hmtnv20.*`, `qcom/gen80100_*`); `pd-mapper`/`tqftpserv` read `.jsn`/`.mbn` straight from `/lib/firmware`; and initrd's `makeModulesClosure` copies by plain name. `regulatory.db` is *not* vendored — `pkgs.wireless-regdb` provides it.
5. **Mandatory Boot `kernelParams`:**
   - `nokaslr` + `efi=novamap`: required for Qualcomm EL2 UEFI stub.
   - `arm-smmu.disable_bypass=0` + `clk_ignore_unused` + `pd_ignore_unused` + `regulator_ignore_unused`: preserve UEFI-initialized rails/clocks/SMMU mappings during early boot (boot-only, zero suspend impact).
   - `mem_sleep_default=s2idle`: prevents `echo mem` from entering unsupported PSCI `deep` sleep.
   - `modprobe.blacklist=qcom_iris,qcom_camss`: prevents video/camera coldplug hangs.
