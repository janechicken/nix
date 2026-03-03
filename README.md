# NixOS Configuration - Disaster Recovery & Installation Guide

This repository contains NixOS and Home Manager configurations for multiple hosts. This guide explains how to recover from a complete system loss (nuked SSD) or install a new system using these configurations.

## Quick Recovery Workflow

If you have a working NixOS installation with this configuration already set up:

```bash
# Update system
nixos-rebuild switch --flake .#HOSTNAME

# Update home-manager configuration
home-manager switch --flake .#HOSTNAME
```

If you need to clone and set up from scratch on an existing NixOS system:

```bash
# Clone repository
sudo git clone https://github.com/username/nix-config /etc/nixos

# Navigate to repository
cd /etc/nixos

# Enable flakes (if not already enabled)
echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf

# Apply system configuration
sudo nixos-rebuild switch --flake .#HOSTNAME

# Install nh for future use (optional)
sudo nix profile install nixpkgs#nh

# Apply home-manager configuration (as regular user)
home-manager switch --flake .#HOSTNAME
```

## Complete Disaster Recovery (Nuked SSD)

### Prerequisites

1. **USB Drive with:**
   - NixOS Live ISO (latest unstable recommended)
   - Age private key file (`keys.txt`) for secret decryption
   - Encrypted `secrets.yaml` (optional, if using secrets)

2. **Backup Sources:**
   - This repository (GitHub or local backup)
   - Age private key (essential for secret decryption)

3. **Hardware Preparation:**
   - FIDO2 security key (if using LUKS+FIDO2 encryption)
   - Secure boot disabled (recommended for FIDO2 setup)

### Step 1: Boot from Live USB

1. Insert USB drive and boot computer
2. Enter UEFI/BIOS (usually F2, F12, Del, or Esc)
3. Select USB as boot device
4. Boot into NixOS Live environment

### Step 2: Network Configuration

#### Ethernet (automatic):
```bash
ip link show
ping google.com
```

#### Wi-Fi (manual):
```bash
sudo systemctl start NetworkManager
nmcli device wifi list
nmcli device wifi connect "SSID" password "password"
```

### Step 3: Disk Partitioning & Encryption

#### Option A: Manual Partitioning (LUKS + Btrfs)

```bash
# Identify disk (usually /dev/nvme0n1 or /dev/sda)
lsblk

# Create partitions
sudo parted /dev/nvme0n1 -- mklabel gpt
sudo parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 512MiB
sudo parted /dev/nvme0n1 -- mkpart primary 512MiB 100%

# Set up LUKS encryption
sudo cryptsetup luksFormat /dev/nvme0n1p2
sudo cryptsetup open /dev/nvme0n1p2 cryptroot

# Format partitions
sudo mkfs.fat -F 32 -n boot /dev/nvme0n1p1
sudo mkfs.btrfs -L nixos /dev/mapper/cryptroot

# Create Btrfs subvolumes
sudo mount /dev/mapper/cryptroot /mnt
sudo btrfs subvolume create /mnt/@
sudo btrfs subvolume create /mnt/@home
sudo umount /mnt

# Mount with subvolumes
sudo mount -o compress=zstd,noatime,subvol=@ /dev/mapper/cryptroot /mnt
sudo mkdir -p /mnt/{boot,home}
sudo mount /dev/nvme0n1p1 /mnt/boot
sudo mount -o compress=zstd,noatime,subvol=@home /dev/mapper/cryptroot /mnt/home
```

#### Option B: LUKS with FIDO2 (as used in jane-pc)

```bash
# Setup LUKS with FIDO2 token
sudo cryptsetup luksFormat /dev/nvme0n1p2 --type luks2
sudo systemd-cryptenroll --fido2-device=auto /dev/nvme0n1p2

# Open encrypted volume
sudo cryptsetup open /dev/nvme0n1p2 cryptroot

# Continue with formatting as above
```

### Step 4: Clone Configuration Repository

```bash
# Clone to /mnt/etc/nixos (installation target)
sudo git clone https://github.com/username/nix-config /mnt/etc/nixos

# OR if you have a local copy on USB:
sudo mount /dev/sdX1 /mnt/usb
sudo cp -r /mnt/usb/nix-config /mnt/etc/nixos/
```

### Step 5: Generate Hardware Configuration

```bash
# Generate hardware-specific config
sudo nixos-generate-config --root /mnt

# Compare with existing config (if available)
diff /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/HOSTNAME/hardware-configuration.nix

# If different, update repository config
sudo cp /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/HOSTNAME/
```

### Step 6: Configure Host-Specific Settings

Edit `/mnt/etc/nixos/hosts/HOSTNAME/configuration.nix`:

1. **Update hostname** (if different):
   ```nix
   networking.hostName = "new-hostname";
   ```

2. **Update disk UUIDs** (if changed):
   ```nix
   boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/NEW-UUID";
   fileSystems."/".device = "/dev/disk/by-uuid/NEW-UUID";
   ```

3. **Update user configuration** (if different username):
   ```nix
   users.users.username = {
     isNormalUser = true;
     extraGroups = [ "wheel" "audio" "video" "input" "networkmanager" ];
   };
   ```

### Step 7: Set Up Secret Management

#### Copy age key from USB:
```bash
# Mount USB if not already mounted
sudo mount /dev/sdX1 /mnt/usb

# Create age directory and copy key
mkdir -p /mnt/etc/nixos/.config/sops/age
sudo cp /mnt/usb/keys.txt /mnt/etc/nixos/.config/sops/age/

# Set permissions
sudo chmod 600 /mnt/etc/nixos/.config/sops/age/keys.txt

# Copy encrypted secrets (if available)
sudo cp /mnt/usb/secrets.yaml /mnt/etc/nixos/secrets/
```

### Step 8: Install NixOS

```bash
# Navigate to repository
cd /mnt/etc/nixos

# Install using flake configuration
sudo nixos-install --flake .#HOSTNAME

# Set root password when prompted
```

### Step 9: Post-Installation Setup

1. **Reboot** and remove USB drive
2. **Login** with root password
3. **Set user password**:
   ```bash
   passwd username
   ```

4. **Switch to user account**:
   ```bash
   su - username
   ```

5. **Copy age key to user directory**:
   ```bash
   mkdir -p ~/.config/sops/age
   sudo cp /etc/nixos/.config/sops/age/keys.txt ~/.config/sops/age/
   chmod 600 ~/.config/sops/age/keys.txt
   ```

6. **Enable flakes** (if not already enabled):
   ```bash
   echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf
   ```

7. **Apply home-manager configuration**:
   ```bash
   home-manager switch --flake /etc/nixos#HOSTNAME
   ```

8. **Update system** (optional, if you installed nh):
   ```bash
   # Install nh for easier future updates
   sudo nix profile install nixpkgs#nh

   # Use nh for system updates
   nh os switch
   ```

## Applying Configuration to Existing NixOS

If you have a working NixOS installation and want to apply these configurations:

### Option A: Fresh Clone & Switch

```bash
# Backup existing configuration (optional)
sudo mv /etc/nixos /etc/nixos.backup

# Clone repository
sudo git clone https://github.com/username/nix-config /etc/nixos

# Navigate and switch
cd /etc/nixos
nh os switch .#HOSTNAME
nh home switch
```

### Option B: Merge with Existing Configuration

```bash
# Clone to temporary location
git clone https://github.com/username/nix-config ~/nix-config-new

# Compare and merge
diff -r /etc/nixos ~/nix-config-new

# Copy specific modules or hosts
sudo cp -r ~/nix-config-new/modules/ /etc/nixos/
sudo cp -r ~/nix-config-new/hosts/HOSTNAME/ /etc/nixos/hosts/

# Update flake.nix if needed
sudo cp ~/nix-config-new/flake.nix /etc/nixos/

# Switch to new configuration
cd /etc/nixos
nh os switch .#HOSTNAME
```

## Host Configuration Examples

### jane-pc (Desktop with FIDO2+LUKS)
- LUKS encryption with FIDO2 token
- Btrfs with compression
- Awesome WM desktop environment
- Full multimedia and gaming setup

### omen (Server/Laptop)
- Simpler disk setup
- Server-oriented packages
- Can be migrated to jane-laptop

## Adding a New Host Configuration

### Overview
Adding a new host involves creating configuration files in the `hosts/` directory and updating the flake. This guide assumes you're familiar with NixOS configuration basics.

### Host Directory Structure
```
hosts/NEW_HOSTNAME/
├── configuration.nix      # NixOS system configuration
├── home.nix               # Home Manager configuration (optional)
├── hardware-configuration.nix  # Generated hardware-specific config
└── [optional] disk-config.nix  # Disko disk partitioning config
```

### Step 1: Create Host Directory
```bash
mkdir -p hosts/NEW_HOSTNAME
```

### Step 2: Create Configuration Files

#### A. configuration.nix (System Configuration)
Create `hosts/NEW_HOSTNAME/configuration.nix`:

```nix
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core.nix
    # Add additional modules as needed
    # ../../modules/desktop.nix        # For desktop hosts
    # ../../modules/graphics.nix      # For GPU support
    # ../../modules/audio.nix          # For audio support
    inputs.sops-nix.nixosModules.sops # For secrets management
    ../../secrets/sops-nix.nix        # If using secrets
  ];

  networking.hostName = "NEW_HOSTNAME";
  
  # Enable networking
  networking.networkmanager.enable = true;
  
  # Set time zone
  time.timeZone = "America/New_York";
  
  # Configure internationalisation
  i18n.defaultLocale = "en_US.UTF-8";
  
  # User configuration
  users.users.username = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
  };
  
  # Enable OpenSSH (optional)
  services.openssh.enable = true;
  
  # Boot configuration
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiSupport = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Filesystem configuration (update with actual UUIDs)
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx";
    fsType = "ext4";
  };
  
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/yyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy";
    fsType = "vfat";
  };
  
  # Swap (if needed)
  swapDevices = [ ];
  
  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  system.stateVersion = "25.05";
}
```

#### B. home.nix (Home Manager Configuration) - Optional
Create `hosts/NEW_HOSTNAME/home.nix` if you want user-specific configuration:

```nix
{ config, pkgs, inputs, ... }:

{
  imports = [
    # Import user modules
    # ../../modules/git.nix
    # ../../modules/terminal.nix
    # ../../modules/browsers.nix
    ../../secrets/home-secrets.nix # If using home-manager secrets
  ];

  home.username = "username";
  home.homeDirectory = "/home/username";
  
  # User packages
  home.packages = with pkgs; [
    # Add user packages here
  ];
  
  # Dotfile management
  home.file.".config/nvim" = {
    recursive = true;
    source = ../../dotfiles/nvim;
  };
  
  home.stateVersion = "25.05";
}
```

#### C. Generate hardware-configuration.nix
On the target machine:
```bash
# Boot from Live USB
sudo nixos-generate-config --root /mnt
sudo cp /mnt/etc/nixos/hardware-configuration.nix hosts/NEW_HOSTNAME/
```

### Step 3: Update flake.nix

Edit `flake.nix` to add the new host:

```nix
nixosConfigurations = {
  jane-pc = nixpkgs.lib.nixosSystem { /* ... */ };
  omen = nixpkgs.lib.nixosSystem { /* ... */ };
  NEW_HOSTNAME = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [ ./hosts/NEW_HOSTNAME/configuration.nix ];
  };
};

homeConfigurations = {
  "jane@jane-pc" = home-manager.lib.homeManagerConfiguration { /* ... */ };
  "root@omen" = home-manager.lib.homeManagerConfiguration { /* ... */ };
  "username@NEW_HOSTNAME" = home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    extraSpecialArgs = { inherit inputs; };
    modules = [ ./hosts/NEW_HOSTNAME/home.nix ];
  };
};
```

### Step 4: Add Secrets (Optional)

If using sops-nix for secrets:

1. Add host to `secrets/secrets.yaml`:
```yaml
NEW_HOSTNAME:
  age: "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  # Age public key
```

2. Add secret references in configuration:
```nix
sops.secrets."secret_name" = {
  path = "/run/secrets/secret_name";
};
```

### Step 5: Test Configuration

```bash
# Test system build
nh os build .#NEW_HOSTNAME

# Test home-manager build (if applicable)
nh home build .#username@NEW_HOSTNAME

# If builds succeed, apply configuration
nh os switch .#NEW_HOSTNAME
nh home switch .#username@NEW_HOSTNAME
```

### Module Selection Guide

#### Desktop Host (like jane-pc)
```nix
imports = [
  ./hardware-configuration.nix
  ../../modules/core.nix
  ../../modules/desktop.nix        # Desktop environment
  ../../modules/graphics.nix       # GPU drivers
  ../../modules/audio.nix          # Audio support
  ../../modules/steam.nix          # Gaming
  ../../modules/opencode.nix       # Development tools
  inputs.sops-nix.nixosModules.sops
  ../../secrets/sops-nix.nix
];
```

#### Server Host (like omen)
```nix
imports = [
  ./hardware-configuration.nix
  ../../modules/core.nix
  # Add server-specific modules
  # ../../modules/syncthing.nix
  inputs.sops-nix.nixosModules.sops
  ../../secrets/sops-nix.nix
];
```

#### Laptop Host
```nix
imports = [
  ./hardware-configuration.nix
  ../../modules/core.nix
  ../../modules/desktop.nix
  # Laptop optimizations
  services.tlp.enable = true;
  services.thermald.enable = true;
  services.upower.enable = true;
  powerManagement.enable = true;
];
```

### Common Issues & Solutions

#### Missing hardware-configuration.nix
```bash
Error: The option `fileSystems' is used but not defined.
```
**Solution:** Generate on target hardware with `nixos-generate-config`

#### Flake Reference Error
```bash
error: flake 'git+file:///etc/nixos' does not provide attribute 'nixosConfigurations.NEW_HOSTNAME'
```
**Solution:** Ensure host is added to `nixosConfigurations` in `flake.nix`

#### Module Not Found
```bash
error: attribute 'desktop' missing
```
**Solution:** Check module path and ensure it exists in `modules/` directory

#### Secret Decryption Failed
```bash
error: secret 'xxx' not found
```
**Solution:** Verify host is added to `secrets/secrets.yaml` and age key is correct

### Example: Creating a Laptop Host

1. **Create directory and basic config:**
```bash
mkdir hosts/jane-laptop
cp hosts/jane-pc/configuration.nix hosts/jane-laptop/
cp hosts/jane-pc/home.nix hosts/jane-laptop/
```

2. **Update configuration.nix:**
```nix
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core.nix
    ../../modules/desktop.nix
    ../../modules/graphics.nix
    ../../modules/audio.nix
    inputs.sops-nix.nixosModules.sops
    ../../secrets/sops-nix.nix
  ];

  networking.hostName = "jane-laptop";
  
  # Laptop optimizations
  services.tlp.enable = true;
  services.thermald.enable = true;
  services.upower.enable = true;
  powerManagement.enable = true;
  
  # Battery monitoring
  services.battery-notifier.enable = true;
  
  # WiFi power saving
  networking.wireless.iwConfig = {
    "wlan0" = {
      powerSave = true;
    };
  };
  
  # Rest of configuration...
}
```

3. **Update flake.nix** with new host
4. **Generate hardware config** on the laptop
5. **Test and apply**

### Tips for Success

1. **Start Simple:** Begin with minimal configuration, add modules gradually
2. **Test Builds:** Use `nh os build` before switching
3. **Use Version Control:** Commit changes frequently
4. **Backup Existing Config:** Before major changes
5. **Reference Existing Hosts:** Use jane-pc and omen as templates

## Secret Management

### File Locations
- **Age private key**: `~/.config/sops/age/keys.txt` (user) or `/var/lib/sops-nix/key.txt` (system)
- **Encrypted secrets**: `secrets/secrets.yaml`
- **Decrypted secrets**: `/run/secrets/` (tmpfs)

### Adding New Secrets
1. Add secret to `secrets/secrets.yaml`
2. Reference in configuration:
   ```nix
   sops.secrets."secret_name" = {
     path = "/run/secrets/secret_name";
   };
   ```

### Age Key on USB
When preparing your USB drive:
```
USB Structure:
├── nixos.iso
├── keys.txt (age private key)
└── nix-config/ (optional, full repository backup)
```

## Troubleshooting

### Build Failures
```bash
# Check evaluation
nix eval .#nixosConfigurations.HOSTNAME.config.system.build.toplevel

# Build dry run
nh os build .#HOSTNAME

# Check for syntax errors
nix fmt
nil fmt
```

### Disk/Encryption Issues
```bash
# Check disk UUIDs
sudo blkid

# Test LUKS opening
sudo cryptsetup open /dev/nvme0n1p2 test-crypt

# Check FIDO2 token
systemd-cryptenroll --fido2-device=list
```

### Network Issues
```bash
# Restart network
sudo systemctl restart NetworkManager

# Check connectivity
ping google.com
```

### Missing age Key
If secrets fail to decrypt:
```bash
# Check age key location
ls -la ~/.config/sops/age/keys.txt

# Verify key permissions
chmod 600 ~/.config/sops/age/keys.txt

# Test decryption
nix-shell -p sops --run "sops -d secrets/secrets.yaml"
```

## Maintenance Commands

### System Updates
```bash
# Update flake inputs
nix flake update

# Update system
nh os switch

# Update home-manager
nh home switch

# Clean old generations
sudo nix-collect-garbage -d
```

### Configuration Management
```bash
# Check current generation
nixos-rebuild list-generations

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Test new configuration
nh os test .#HOSTNAME
```

## Backup Strategy

### Essential Files to Backup
1. **Repository**: `git clone --mirror` or regular backup
2. **Age keys**: `~/.config/sops/age/keys.txt`
3. **Encrypted secrets**: `secrets/secrets.yaml`
4. **User data**: Home directory, documents, etc.

### Automated Backup Example
```bash
# Backup script example
#!/bin/bash
BACKUP_DIR="/path/to/backup/$(date +%Y-%m-%d)"

# Backup repository
git clone --mirror /etc/nixos $BACKUP_DIR/nix-config.git

# Backup age key
mkdir -p $BACKUP_DIR/.config/sops/age
cp ~/.config/sops/age/keys.txt $BACKUP_DIR/.config/sops/age/

# Backup secrets
cp /etc/nixos/secrets/secrets.yaml $BACKUP_DIR/
```

## Support

For issues with this configuration:
1. Check build output: `nh os build .#HOSTNAME -v`
2. Review module imports in host configuration
3. Test with minimal configuration
4. Consult NixOS community resources

## Notes

- This configuration uses flakes; ensure `nix.settings.experimental-features = [ "nix-command" "flakes" ];` is set
- Disk UUIDs may change after repartitioning; update `hardware-configuration.nix` accordingly
- FIDO2 setup requires compatible token and may need secure boot disabled
- Always test configuration with `nh os build` before switching