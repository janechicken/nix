# AGENTS.md - Agent Coding Guidelines for Nix Config

This repository contains NixOS and Home Manager configurations using flakes.

## Build Commands

### NixOS System Build
```bash
# Build and switch to new configuration
nh os switch .

# Build only (dry run)
nh os build .

# Test configuration without switching
nh os test .

```

### Home Manager Build
```bash
# Switch home-manager configuration
nh home switch .

```

### Using nh (recommended)
```bash
# Rebuild and switch OS (from home directory)
nh os switch

# Rebuild home manager
nh home switch
```

### Linting/Formatting
```bash
# Format Nix files with nixfmt
nix fmt

# Check Nix files with nil (language server)
nil fmt

# Evaluate configuration (check for errors)
nix eval .#nixosConfigurations.jane-pc.config.system.build.toplevel
```

### Updating
```bash
# Update flake inputs
nix flake update

# Update a specific input
nix flake update nixpkgs
```

## Code Style Guidelines

### File Organization
- **Modules**: Place in `modules/` directory, one file per concern
- **Hosts**: Place in `hosts/<hostname>/` with `configuration.nix`, `home.nix`, `hardware-configuration.nix`
- **Secrets**: Place in `secrets/` directory (never commit unencrypted secrets)
- **Flakes**: Root `flake.nix` defines inputs and outputs

### Nix File Structure

```nix
{ config, lib, pkgs, inputs, ... }:

{
  # Imports at top
  imports = [
    ./hardware-configuration.nix
    ../../modules/core.nix
  ];

  # Options in alphabetical order within categories
  # (or grouped logically by function)

  # Services
  services = {
    foo.enable = true;
  };

  # Programs
  programs = {
    bar.enable = true;
  };

  # Environment
  environment.systemPackages = with pkgs; [
    package1
    package2
  ];

  # Hardware
  hardware.graphics.enable = true;

  # Users
  users.users.username = {
    isNormalUser = true;
    extraGroups = [ "wheel" "audio" ];
  };

  # System packages
  environment.systemPackages = with pkgs; [ ];
}
```

### Naming Conventions
- **Files**: `kebab-case.nix` (e.g., `opencode.nix`, `home-manager.nix`)
- **Modules**: Descriptive nouns, e.g., `git.nix`, `audio.nix`, `steam.nix`
- **Hosts**: Lowercase hostname, e.g., `jane-pc`, `omen`
- **Options**: Follow NixOS option naming (`services.<name>`, `programs.<name>`)

### Import Paths
- Use relative imports: `./file.nix` (same directory), `../../modules/core.nix` (parent)
- Always use `../../` prefix for going up directories from host config
- Secrets files use `./secrets.yaml` (relative to secrets directory)

### Formatting
- Use 2-space indentation
- Trailing commas are encouraged (Nix is flexible here)
- Align attribute sets for readability:
  ```nix
  boot = {
    initrd.kernelModules = [ "i915" ];
    loader.grub.enable = true;
  };
  ```
- Use `lib.mkEnableOption` or `lib.mkIf` for conditional config
- Prefer `with pkgs;` for package lists

### Options and Types
- Use proper option paths from NixOS options search
- Specify types when defining custom options
- Use `enable = true` pattern for boolean options

### Secrets Management
- **Never** commit unencrypted secrets
- Use `sops-nix` for secrets (see `secrets/sops-nix.nix`)
- Encrypted secrets go in `secrets/secrets.yaml`
- Age keys: `~/.config/sops/age/keys.txt` (user), `/var/lib/sops-nix/key.txt` (system)
- Use `/run/secrets/` for system secrets (tmpfs, available at boot)

### Common Patterns

#### With packages:
```nix
environment.systemPackages = with pkgs; [
  package1
  package2
];
```

#### With lib:
```nix
# Conditional config
lib.mkIf config.services.foo.enable {
  # config here
}

# Enable option pattern
services.bar.enable = lib.mkEnableOption "bar service";
```

#### With inputs (flake modules):
```nix
imports = [
  inputs.sops-nix.nixosModules.sops
];
```

### Error Handling
- Run `nh os build .` and `nh home build .` first to catch errors
- Check evaluation with `nix eval .#nixosConfigurations.<host>.config.<option>`
- Use `nix logs` to debug failed builds

### Testing Changes
1. Test build: `nh os test .` and `nh home test .`

### OpenCode Agents
This project includes custom opencode agents (see `modules/opencode.nix`):
- `@reviewer` - Reviews code for security, performance, and standards
- `@docs-generator` - Generates markdown documentation (no emojis)

### OpenCode Commands
- `/test` - Runs tests for the Nix configuration (builds both NixOS and home-manager)
- `/review` - Reviews git changes (built-in command)

### Don'ts
- Don't hardcode paths like `/home/jane` - use `config.users.users.jane.homeDirectory`
- Don't commit encrypted secrets or age keys
- Don't use `nix-env` for system packages (use NixOS options)
- Don't mix NixOS and Home Manager secrets management (pick one approach)
- Don't run `nh home switch .` or `nh os switch .` yourself, leave it to the user to switch
