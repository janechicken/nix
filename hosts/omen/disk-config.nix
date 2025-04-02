{ lib, ... }: {
  disko.devices = {
    disk.main = {
      device = lib.mkDefault "/dev/nvme0n1";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            priority = 1;
            name = "ESP";
            start = "1M";
            end = "512M"; # Increased size for better compatibility
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/" = {
                  mountpoint = "/";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "/home" = { # Added recommended subvolume
                  mountpoint = "/home";
                  mountOptions = [ "compress=zstd" ];
                };
              };
            };
          };
        };
      };
    };

    disk.storage = {
      type = "disk";
      device = "/dev/sda";
      content = {
        type = "gpt";
        partitions = {
          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "zstorage";
            };
          };
        };
      };
      zpool.zstorage = {
        type = "zpool";
        # Disable pool root mount
        rootFsOptions = {
          canmount = "off"; # Critical: prevents pool root mount
          mountpoint = "none"; # Ensures no /zstorage appears
        };
        # Only mount the storage dataset
        datasets.storage = {
          type = "zfs_fs";
          mountpoint = "/storage"; # This will be your only visible mount
          options = {
            compression = "zstd";
            atime = "off";
            xattr = "sa"; # Better performance
            acltype = "posixacl"; # Standard permissions
          };
        };
      };
    };
  };

  # Required ZFS system configuration
  boot = {
    supportedFilesystems = [ "zfs" ];
    zfs = { requestEncryptionCredentials = true; };
  };
  networking.hostId = "deadbeef";
}
