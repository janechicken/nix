# AGENTS.md

NixOS + Home Manager flake config. 2 hosts: `jane-pc` (`x86_64-linux`) and `yogabook` (`aarch64-linux`, Snapdragon X2 Plus / Mahua).

## Hosts

| Host | Type | GPU | Special |
|------|------|-----|---------|
| `jane-pc` | desktop | Intel (modesetting) | FIDO2+LUKS, Hyprland Wayland, gaming, IDA Pro |
| `yogabook` | laptop | Snapdragon X2 Plus (Adreno X2-45, `mesa-mahua`) | FIDO2+LUKS (initrd `pmic_glink`), Hyprland Wayland @ 1.25x, custom Linux 7.4-rc3 Kalambo/Mahua kernel |

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

Proprietary Lenovo Windows DriverStore blobs (ADSP/CDSP `.mbn`/`.jsn`/`.elf`, WCN7850 BT NV `hmtnv20.b112`, `Lenovo-Yoga-Slim7-14Q8Y11-tplg.bin`) are intentionally **not** committed to this public repo and live in `/var/lib/mahua-firmware` (`firmware_class.path=/var/lib/mahua-firmware`). Only the 3 GPU blobs (`gen80100_{sqe,gmu,aqe}`) are staged in `hosts/yogabook/firmware/` for initrd display bring-up.

## Conventions

- **Files**: `kebab-case.nix`
- **Imports**: `./file.nix` (same dir), `../../modules/<name>.nix` (from host configs)
- **Indent**: 2 spaces
- **User path**: Use `config.users.users.jane.home` (NixOS) / `config.home.homeDirectory` (Home Manager), never `/home/jane`
- **Package lists**: `environment.systemPackages = with pkgs; [ ... ];`

## Don'ts

- No `nix-env` for system packages
- No committing unencrypted secrets, age keys, or proprietary firmware blobs
- No `nh os switch .` / `nh home switch .` — build only
- No hardcoded `/home/jane` paths
- No `apt`/`pip`/`npm` for system packages (use `nix-shell -p <pkg>` instead)
