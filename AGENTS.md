# AGENTS.md

NixOS + Home Manager flake config. 2 hosts: `jane-pc` (`x86_64-linux`) and `yogabook` (`aarch64-linux`, Snapdragon X2 Plus / Mahua).

## Hosts

| Host | Type | GPU | Special |
|------|------|-----|---------|
| `jane-pc` | desktop | Intel (modesetting) | FIDO2+LUKS, Awesome WM, gaming, IDA Pro |
| `yogabook` | laptop | Snapdragon X2 Plus (Adreno X2-45, Mesa) | FIDO2+LUKS, Awesome WM @ 120 DPI (125%), custom Linux 7.4-rc3 Mahua kernel + v8 eDP PHY fix |

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
- **overlays/**: `default.nix` composes `ida-pro.nix`, `joyshockmapper.nix`, `mahua-kernel.nix`, `mdpls.nix`, `omp.nix`.
- **pkgs/**: Custom derivations:
  - `pkgs/ida-pro/` + `pkgs/ida-pro-mcp/` — IDA Pro wrapper & MCP (x86_64 only)
  - `pkgs/joyshockmapper/` — JoyShockMapper custom curve fork
  - `pkgs/linux-mahua/` — Linux 7.4-rc3 + 10 verified Mahua/14Q8Y11 patches (`linuxPackages_mahua`)
  - `pkgs/mdpls/` — Markdown Preview Language Server
  - `pkgs/omp/` — oh-my-pi release binary (`x86_64-linux` + `aarch64-linux`)
- **Arch gating**: Shared modules (`core.nix`, `audio.nix`, `reaper.nix`, `discord.nix`, `omp.nix`) gate x86_64-only packages (`wine`, `yabridge`, 32-bit ALSA, `discord`, `ida-pro`) via `pkgs.stdenv.hostPlatform.isx86_64` (`discord.nix` installs `vesktop` on `aarch64-linux`).
- **stateVersion**: `25.05` on all hosts.

## Secrets (sops-nix)

- System age key: `/var/lib/sops-nix/keys.txt`
- User age key: `~/.config/sops/age/keys.txt`
- Encrypted secrets: `secrets/secrets.yaml` (`.sops.yaml` defines authorized age keys)
- Decrypted at `/run/secrets/` (tmpfs)
- New host setup: either copy existing `/var/lib/sops-nix/keys.txt`, or add new host age pubkey to `.sops.yaml` and run `sops updatekeys secrets/secrets.yaml`.

## Lenovo 83QR Firmware (`yogabook`)

Proprietary Lenovo Windows DriverStore blobs (ADSP/CDSP `.mbn`/`.jsn`/`.elf`, WCN7850 BT NV `hmtnv20.b112`, Adreno `gen80100_*`, `Lenovo-Yoga-Slim7-14Q8Y11-tplg.bin`) are intentionally **not** committed to this public repo. Copy them to `/var/lib/mahua-firmware` during install; `yogabook` loads them via `firmware_class.path=/var/lib/mahua-firmware`.

## Conventions

- **Files**: `kebab-case.nix`
- **Imports**: `./file.nix` (same dir), `../../modules/<name>.nix` (from host configs)
- **Indent**: 2 spaces
- **User path**: Use `config.users.users.jane.homeDirectory`, never `/home/jane`
- **Package lists**: `environment.systemPackages = with pkgs; [ ... ];`

## Don'ts

- No `nix-env` for system packages
- No committing unencrypted secrets, age keys, or proprietary firmware blobs
- No `nh os switch .` / `nh home switch .` — build only
- No hardcoded `/home/jane` paths
- No `apt`/`pip`/`npm` for system packages (use `nix-shell -p <pkg>` instead)
