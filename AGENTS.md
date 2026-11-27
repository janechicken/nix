# AGENTS.md

NixOS + Home Manager flake config. 2 hosts: `jane-pc` (`x86_64-linux`) and `yogabook` (`aarch64-linux`, Snapdragon X2 Plus / Mahua).

## Hosts

| Host | Type | GPU | Special |
|------|------|-----|---------|
| `jane-pc` | desktop | Intel (modesetting) | FIDO2+LUKS, Hyprland Wayland, gaming, IDA Pro |
| `yogabook` | laptop | Snapdragon X2 Plus (Adreno X2-45, `mesa-mahua`) | FIDO2+LUKS (initrd **loads the real display stack** — `boot.initrd.kernelModules` has `msm` + `panel_samsung_atna33xc20` + deps and `boot.initrd.extraFirmwarePaths` stages the `qcom/gen80100_*` GPU microcode, because the UEFI GOP scanout dies at `ExitBootServices` so `simpledrm` cannot light the panel; the `mahua-panel-pm` initrd udev rule + unit pin `power/autosuspend_delay_ms=-1` on the `dp-aux` panel to stop its 2 s autosuspend blackout, and the stage-2 `mahua-panel-pm-release` unit drops that pin again), Hyprland Wayland @ 1.25x, custom Linux 7.4-rc3 Kalambo/Mahua kernel |

Shared modules via `hosts/<name>/configuration.nix` (system) + `home.nix` (user).

## Build & Verify

```bash
# Dry-run system build
nh os build .

# Dry-run home-manager build
nh home build .

# Evaluate without building
nix eval .#nixosConfigurations.<host>.config.system.build.toplevel
```

No switching — leave `nh os switch` / `nh home switch` to user. No test framework exists; build verification is the only check.

`yogabook` is `aarch64-linux`: `nix eval` works from any machine, while `nh os build` / `nh home build` should run on the laptop itself (or via `binfmt` / remote builder).

## Format & Update

```bash
nix fmt                          # nixfmt all Nix files
nix flake update                 # update all inputs
nix flake update nixpkgs         # update single input
```

## Architecture

- **flake.nix**: 2 `nixosConfigurations` + 2 `homeConfigurations` via `mkNixos`/`mkHome` helpers, parameterized by system. Home-manager uses per-system `pkgsFor` (overlay pre-applied). NixOS configs apply the overlay via `nixpkgs.overlays`.
- **overlays/**: `default.nix` composes `ida-pro.nix`, `joyshockmapper.nix`, `mahua-kernel.nix`, `mdpls.nix`. **Never override core shared libraries (`mesa`, `alsa-ucm-conf`, `llvm`, etc.) in `overlays/`** — use scoped package names (`alsa-ucm-conf-mahua`) or NixOS module options (`hardware.graphics.package`) to preserve `cache.nixos.org` hits.
- **pkgs/**: Custom derivations:
  - `pkgs/ida-pro/` + `pkgs/ida-pro-mcp/` — IDA Pro wrapper & MCP (x86_64 only)
  - `pkgs/joyshockmapper/` — JoyShockMapper custom curve fork
  - `pkgs/linux-mahua/` — Linux 7.4-rc3 + 14 Kalambo/Mahua/14Q8Y11 patches (`linuxPackages_mahua`); see `hosts/yogabook/BRINGUP.md` for hardware status, verification commands, and invariants
  - `pkgs/mesa-mahua/` — Scoped Mesa with Adreno X2-45 (`0xc144060020`) support for `yogabook` (`hardware.graphics.package`)
  - `pkgs/mdpls/` — Markdown Preview Language Server
- **Agents & editors** (home-manager modules, both hosts): `pi.nix` — pi coding agent via `pi-nix` with the single local `refuseless` provider extension (`dotfiles/pi/extensions/refuseless-provider.ts`) and the x86_64-gated IDA MCP bridge; `t3code.nix` — T3 Code from nixpkgs; `antigravity.nix` — Google Antigravity IDE + ACP server from nixpkgs.
- **Arch gating**: Shared modules (`core.nix`, `audio.nix`, `reaper.nix`, `discord.nix`, `pi.nix`) gate x86_64-only packages (`wine`, `yabridge`, 32-bit ALSA, `discord`, `ida-pro`) via `pkgs.stdenv.hostPlatform.isx86_64` (`discord.nix` installs `vesktop` on `aarch64-linux`).
- **stateVersion**: `25.05` on all hosts.

## Secrets (sops-nix)

- System age key: `/var/lib/sops-nix/keys.txt`
- User age key: `~/.config/sops/age/keys.txt`
- Encrypted secrets: `secrets/secrets.yaml` (`.sops.yaml` defines authorized age keys)
- Decrypted at `/run/secrets/` (tmpfs)
- New host setup: either copy existing `/var/lib/sops-nix/keys.txt`, or add new host age pubkey to `.sops.yaml` and run `sops updatekeys secrets/secrets.yaml`.

## Lenovo 83QR Firmware (`yogabook`)

All proprietary Lenovo 83QR blobs are **tracked in this repo** under `hosts/yogabook/firmware/` (Adreno GPU `qcom/gen80100_{sqe,gmu,aqe}`, ADSP/CDSP `qcom/glymur/LENOVO/83QR/*.mbn`/`.jsn`/`.elf`/`fastrpc_shell_0`, the `qcom/glymur/Lenovo-Yoga-Slim7-14Q8Y11-tplg.bin` audio topology, WCN7850 `ath12k/WCN7850/hw2.0/*`, and BT NV `qca/hmtnv20.*` + `qca/hmtbtfw20.tlv`), and wired **declaratively** into `hardware.firmware` by a local `runCommandLocal "mahua-firmware"` derivation in `hosts/yogabook/configuration.nix` (`compressFirmware = false`, `meta.priority = 1`), so `/lib/firmware` is complete on a fresh install.

- Keep the files **uncompressed**: the kernel tries the plain name before `"$name.zst"`, so they shadow `linux-firmware`'s `.zst` siblings; `pd-mapper`/`tqftpserv` read `.jsn`/`.mbn` directly from `/lib/firmware`; any future initrd staging copies by plain name.
- The 3 GPU blobs exist exactly **once** (`hosts/yogabook/firmware/qcom/gen80100_*`) and reach the kernel through `/lib/firmware` in stage 2 and through `boot.initrd.extraFirmwarePaths` at `/lib/firmware/qcom/` in stage 1. `msm` has **no** `MODULE_FIRMWARE()` entries (it builds the names at run time in `adreno_request_fw()`), so the initrd's `makeModulesClosure` cannot discover them — do not remove `extraFirmwarePaths`, or the GPU component never probes and `msm_dpu` never binds.
- Do **not** vendor `regulatory.db`/`regulatory.db.p7s` — `pkgs.wireless-regdb` (`hardware.wirelessRegulatoryDatabase`) provides them.
- `/var/lib/mahua-firmware` (`firmware_class.path`) is kept only as an **optional override** path for testing a new blob without a rebuild; an empty dir is harmless.
- These are proprietary redistributable-but-not-free blobs; secrets, age keys and unencrypted credentials still never get committed.

## Conventions

- **Files**: `kebab-case.nix`
- **Imports**: `./file.nix` (same dir), `../../modules/<name>.nix` (from host configs)
- **Indent**: 2 spaces
- **User path**: Use `config.users.users.jane.home` (NixOS) / `config.home.homeDirectory` (Home Manager), never `/home/jane`
- **Package lists**: `environment.systemPackages = with pkgs; [ ... ];`

## Don'ts

- No `nix-env` for system packages
- No committing unencrypted secrets or age keys (the tracked `hosts/yogabook/firmware/` blobs are the only sanctioned exception)
- No `nh os switch .` / `nh home switch .` — build only
- No hardcoded `/home/jane` paths
- No `apt`/`pip`/`npm` for system packages (use `nix-shell -p <pkg>` instead)
