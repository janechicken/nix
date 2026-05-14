# AGENTS.md

NixOS + Home Manager flake config. 2 hosts, x86_64-linux only.

## Hosts

| Host | Type | GPU | Special |
|------|------|-----|---------|
| `jane-pc` | desktop | Intel (modesetting) | FIDO2+LUKS, Awesome WM, gaming |
| `jane-laptop` | laptop | NVIDIA (open) | FIDO2+LUKS, TLP, lid switch handling |

Both share modules via `hosts/<name>/configuration.nix` (system) + `home.nix` (user).

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

## Format & Update

```bash
nix fmt                          # nixfmt all Nix files
nix flake update                 # update all inputs
nix flake update nixpkgs         # update single input
```

## Architecture

- **flake.nix**: 2 nixosConfigurations + 2 homeConfigurations. Home-manager uses `pkgsWithOverlay` (overlay pre-applied). NixOS configs use plain `nixpkgs.legacyPackages`.
- **overlays/**: `default.nix` lists overlay files to compose via `nixpkgs.lib.composeManyExtensions`. Currently: `browser-use.nix`.
- **pkgs/**: Custom nixpkgs derivations (`pkgs/browser-use/` — 6 packages for browser-use MCP tool).
- **Dotfiles**: `dotfiles/` (awesome, dunst, kitty, nvim, picom, rofi, zed). Linked via `home.file` in `modules/desktop.nix`.
- **stateVersion**: 25.05 on all hosts.
- **No CI** (no `.github/`).

## Directory Map

| Path | Purpose |
|------|---------|
| `hosts/<name>/` | Per-host config: `configuration.nix`, `home.nix`, `hardware-configuration.nix` |
| `modules/` | 42 shared modules (one file per concern, no subdirs) |
| `overlays/` | nixpkgs overlay definitions (`default.nix` → `browser-use.nix`) |
| `pkgs/` | Custom package derivations |
| `secrets/` | sops-nix encrypted secrets (`secrets.yaml`, `sops-nix.nix`, `home-secrets.nix`) |
| `dotfiles/` | Dotfile directories synced via home-manager |
| `skills/` | Custom opencode skill (`solve-challenge`) |

## Secrets (sops-nix)

- System age key: `/var/lib/sops-nix/keys.txt`
- User age key: `~/.config/sops/age/keys.txt`
- Encrypted secrets: `secrets/secrets.yaml` (`.sops.yaml` defines the sole age key)
- Decrypted at `/run/secrets/` (tmpfs)
- 4 active secrets: `openrouter_api_key`, `deepseek_api_key`, `opencode_api_key`, `ssh_key` (+ `ssh_pubkey`)
- System secrets set as `environment.sessionVariables`; `gpg_key` secret is commented out

## OpenCode (`modules/opencode.nix`)

- **Agents**: `reviewer`, `squad` (dispatcher), `student`, `general`, `general-quick`, `explore`, `eyes`
- **MCP**: browser-use via `uvx --from browser-use[cli] browser-use --mcp`
- **Skills**: CTF skills from `ctf-skills` flake input + local `solve-challenge`
- **Commands**: `/test` (build verification), `/git`, `/solve-challenge`, `/ctf-writeup`, `/breath`
- **Theme**: gruvbox
- **Global style**: terse caveman (set in `context` field)

## Conventions

- **Files**: `kebab-case.nix`
- **Imports**: `./file.nix` (same dir), `../../modules/<name>.nix` (from host configs)
- **Indent**: 2 spaces
- **User path**: Use `config.users.users.jane.homeDirectory`, never `/home/jane`
- **for package lists**: `environment.systemPackages = with pkgs; [ ... ];`

## Don'ts

- No `nix-env` for system packages
- No committing unencrypted secrets or age keys
- No `nh os switch .` / `nh home switch .` — build only
- No hardcoded `/home/jane` paths
