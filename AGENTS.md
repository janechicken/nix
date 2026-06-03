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
| **overlays/**: `default.nix` lists overlay files to compose via `nixpkgs.lib.composeManyExtensions`. Currently: `browser-use.nix`, `ghidra-mcp.nix`.
| **pkgs/**: Custom nixpkgs derivations:
  - `pkgs/browser-use/` — 6 packages (agentmail, browser-use-sdk, bubus, cdp-use, uuid7, default)
  - `pkgs/ghidra-mcp/` — GhidraMCP extension

- **stateVersion**: 25.05 on all hosts.
- **No CI** (no `.github/`).

## Directory Map

| Path | Purpose |
|------|---------|
| `hosts/<name>/` | Per-host config: `configuration.nix`, `home.nix`, `hardware-configuration.nix` |
| `modules/` | 45 shared modules (one file per concern, no subdirs) |
| `overlays/` | nixpkgs overlay definitions (`default.nix` → `browser-use.nix`, `ghidra-mcp.nix`) |
| `pkgs/` | Custom package derivations (browser-use, ghidra-mcp) |
| `secrets/` | sops-nix encrypted secrets (`secrets.yaml`, `sops-nix.nix`, `home-secrets.nix`) |
| `dotfiles/` | Dotfile directories synced via home-manager |
| `skills/` | Custom opencode skill (`solve-challenge`) |

## Secrets (sops-nix)

- System age key: `/var/lib/sops-nix/keys.txt`
- User age key: `~/.config/sops/age/keys.txt`
- Encrypted secrets: `secrets/secrets.yaml` (`.sops.yaml` in project root defines the sole age key)
- Decrypted at `/run/secrets/` (tmpfs)
- 4 active secrets: `deepseek_api_key`, `opencode_api_key`, `ssh_key`, `ssh_pubkey`
  - OpenRouter key was deprecated; only DeepSeek + OpenCode AI API keys are active
- System secrets set as `environment.sessionVariables` (`DEEPSEEK_API_KEY`, `OPENCODE_API_KEY`, `OPENCODE_GO_API_KEY`, `OPENAI_API_KEY`, `OPENAI_MODEL`, `OPENAI_MODEL_FOR_CHAT`, `OPENAI_ENDPOINT`)
- Commented out secret: `gpg_key`

## Agent Skills (`modules/agent-skills.nix`)

- Uses `agent-skills-nix` flake input (home-manager module from `github:Kyure-A/agent-skills-nix`)
- **Sources**:
  - `ctf-skills` — from `github:ljagiello/ctf-skills` flake input
  - `local` — from `../skills/` dir with `solve-challenge`
- **Enabled CTF skills**: `ctf-ai-ml`, `ctf-crypto`, `ctf-forensics`, `ctf-malware`, `ctf-misc`, `ctf-osint`, `ctf-pwn`, `ctf-reverse`, `ctf-web`, `ctf-writeup`
- **Explicit skill**: `solve-challenge` (from local source)
- Target: OpenCode (`targets.opencode.enable = true`)

## OpenCode (`modules/opencode.nix`)

- **Agents**: `reviewer`, `squad` (dispatcher), `student`, `general`, `general-quick`, `explore`, `eyes`
- **MCP**:
  - `browser-use` — via `uvx --from browser-use[cli] browser-use --mcp` (headless disabled, playwright from nix store)
  - `ghidra` — GhidraMCP for reverse engineering
- **Skills**: CTF skills from `ctf-skills` flake input + local `solve-challenge` + `rust-skills` from flake input
- **Commands**: `/test` (build verification), `/git`, `/solve-challenge`, `/ctf-writeup`, `/breath`
- **Theme**: gruvbox
- **Global style**: terse caveman (set in `context` field)
- **Auth**: `OPENCODE_API_KEY` env var (set via sops-nix system-wide)

## Pi Agent (`modules/pi.nix`)

- **Package**: `pi-coding-agent` from nixpkgs
- **Auth**: `OPENCODE_API_KEY` env var (shared with OpenCode, set via sops-nix)
- **Settings**: `~/.pi/agent/settings.json`
  - Provider: `opencode-go`, model: `deepseek-v4-flash`
  - Theme: dark
  - Compaction enabled (reserve 16K, keep 20K recent)
  - Retry enabled (max 3 retries)
- **Extension**: tool-use enforcement — blocks text-only responses without tool calls (enforces research-first behavior)
- **AGENTS.md**: loaded every Pi session with NixOS-specific instructions

## Helix Editor (`modules/helix.nix`)

- 419-line config with full editor setup
- Custom themes, language configs, keybindings

## Ghidra MCP (`modules/ghidra-mcp.nix`)

- Installs `ghidra-mcp` package from nixpkgs overlay
- Symlinks GhidraMCP extension into `~/.ghidra/.ghidra_<version>/Extensions/`

## Flake Inputs

Key flake inputs beyond nixpkgs + home-manager:
- `agent-skills-nix` — agent skills home-manager module
- `ctf-skills` — CTF skill definitions (flake=false)
- `cybersec-skills` — cybersecurity skills (flake=false)
- `rust-skills` — Rust skills (flake=false)
- `sops-nix` — secret management
- `firefox-addons`, `nixcord` — browser extensions, Discord mod
- `disko` — disk partitioning
- `nix-alien`, `nixwrap` — non-NixOS binary compat
- `renix` — Renoise DAW config

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
- No `apt`/`pip`/`npm` for system packages (use `nix-shell -p <pkg>` instead)
