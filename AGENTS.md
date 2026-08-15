# AGENTS.md

NixOS + Home Manager flake config. Single host: jane-pc (x86_64-linux).

## Hosts

| Host | Type | GPU | Special |
|------|------|-----|---------|
| `jane-pc` | desktop | Intel (modesetting) | FIDO2+LUKS, Awesome WM, gaming |

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

## Format & Update

```bash
nix fmt                          # nixfmt all Nix files
nix flake update                 # update all inputs
nix flake update nixpkgs         # update single input
```

## Architecture

- **flake.nix**: 1 nixosConfiguration + 1 homeConfiguration via `mkNixos`/`mkHome` helpers, parameterized by system. Home-manager uses per-system `pkgsFor` (overlay pre-applied). NixOS configs use plain `nixpkgs.legacyPackages`.
| **overlays/**: `default.nix` lists overlay files to compose via `nixpkgs.lib.composeManyExtensions`. Currently: `browser-use.nix`, `ghidra-mcp.nix`, `joyshockmapper.nix`, `mdpls.nix`, `omp.nix`.
| **pkgs/**: Custom nixpkgs derivations:
  - `pkgs/browser-use/` — 6 packages (agentmail, browser-use-sdk, bubus, cdp-use, uuid7, default)
  - `pkgs/ghidra-mcp/` — GhidraMCP extension
  - `pkgs/omp/` — oh-my-pi release binary package

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
| `skills/` | Custom skill (`solve-challenge`) |

## Secrets (sops-nix)

- System age key: `/var/lib/sops-nix/keys.txt`
- User age key: `~/.config/sops/age/keys.txt`
- Encrypted secrets: `secrets/secrets.yaml` (`.sops.yaml` in project root defines the sole age key)
- Decrypted at `/run/secrets/` (tmpfs)
- sops decrypts at build time: a new host needs its age pubkey in `.sops.yaml`, then `sops updatekeys secrets/secrets.yaml`
- 7 active secrets: `deepseek_api_key`, `cursor_api_key`, `openrouter_api_key`, `ssh_key`, `ssh_pubkey`, `cheapcompute_api_key`, `nanogpt_api_key`
  - `openrouter_api_key` enables the OpenRouter provider (default, e.g. `openrouter/~deepseek/deepseek-v4-flash-latest`), `cursor_api_key` enables the cursor-sdk extension (e.g. `cursor/kimi-k3`), `cheapcompute_api_key`  + `nanogpt_api_key` feed the omp `models.yml` custom providers
- System secrets set as `environment.sessionVariables` (`DEEPSEEK_API_KEY`, `CURSOR_API_KEY`, `OPENROUTER_API_KEY`, `OPENAI_API_KEY`, `OPENAI_MODEL`, `OPENAI_MODEL_FOR_CHAT`, `OPENAI_ENDPOINT`)
- Commented out secret: `gpg_key`

## Agent Skills (`modules/agent-skills.nix`)

- Uses `agent-skills-nix` flake input (home-manager module from `github:Kyure-A/agent-skills-nix`)
- **Sources**:
  - `ctf-skills` — from `github:ljagiello/ctf-skills` flake input
  - `local` — from `../skills/` dir with `solve-challenge`
- **Enabled CTF skills**: `ctf-ai-ml`, `ctf-crypto`, `ctf-forensics`, `ctf-malware`, `ctf-misc`, `ctf-osint`, `ctf-pwn`, `ctf-reverse`, `ctf-web`, `ctf-writeup`
- **Explicit skill**: `solve-challenge` (from local source)
- **Targets**: OpenCode (`targets.opencode.enable = true`) + omp (`.omp/agent/skills`)

## OpenCode (`modules/opencode.nix`)

- **Agents**: `reviewer`, `squad` (dispatcher), `student`, `general`, `general-quick`, `explore`, `eyes` (vision via qwen/qwen3.7-flash)
- **MCP**:
  - `browser-use` — via `uvx --from browser-use[cli] browser-use --mcp` (headless disabled, playwright from nix store)
  - `ghidra` — GhidraMCP for reverse engineering
- **Skills**: CTF skills from `ctf-skills` flake input + local `solve-challenge` + `rust-skills` from flake input
- **Commands**: `/test` (build verification), `/git`, `/solve-challenge`, `/ctf-writeup`, `/breath`
- **Theme**: gruvbox
- **Global style**: terse caveman (set in `context` field)
- **Auth**: `OPENROUTER_API_KEY` env var (set via sops-nix system-wide)

## oh-my-pi Agent (`modules/omp.nix`) — replaces pi

- **Package**: `pkgs.omp` from `overlays/omp.nix` — fetches the per-arch release binary (`omp-linux-x64` / `omp-linux-arm64`) from GitHub (`can1357/oh-my-pi`), `patchelf`'d for the NixOS glibc loader (`dontStrip`; autoPatchelf would mangle the embedded Bun runtime). Not in nixpkgs.
- **Config**: `~/.omp/agent/` (YAML), tracked as dotfiles (`dotfiles/.omp/agent/`) and wired via `modules/omp.nix` (same pattern as awesome/rofi/zed). `models.yml` / theme are store-linked; `config.yml` is seeded from the dotfile by `home.activation.writeOmpConfig` into a writable copy (omp mutates it at runtime):
  - **Providers** (`models.yml`): custom OpenAI-compatible `nanogpt` + `cheapcompute`, both with `discovery: openai-models-list` (runtime `GET /models`), reading `NANOGPT_API_KEY` / `CHEAPCOMPUTE_API_KEY` (sops sessionVariables)
  - **Model roles**: default/smol `nanogpt/deepseek/deepseek-v4-flash-0731`, vision `nanogpt/qwen/qwen3.7-flash` (from the removed eyes subagent)
  - **Theme**: custom `autumn-dark` (ported from old pi theme, `~/.omp/agent/themes/autumn-dark.json`, selected via `theme.dark`)
  - **Rules**: caveman contract in `~/.omp/agent/APPEND_SYSTEM.md`
  - **Permissions**: `tools.approval` auto-approves read-only tools; `bash.patterns` denies `rm -rf`, prompts `sudo`
  - **Compaction** enabled (reserve 16K, keep 20K), **retry** enabled (max 3)
  - **hideThinkingBlock**: true
- **Agents**: `~/.omp/agent/agents/*.md` (researcher = web research)
- **Skills**: via `modules/agent-skills.nix` target `omp` → `~/.omp/agent/skills`
- **Auth**: `OPENROUTER_API_KEY` env var (set via sops-nix system-wide)

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
