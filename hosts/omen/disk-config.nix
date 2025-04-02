{ lib, ... }: {
  disko.devices = {
    disk.main = {
      device = lib.mkDefault "/dev/nvme0n1";
      type = "disk";
      content = {
        type = "gpt";  # Added missing partition table type
        partitions = {
          ESP = {
            priority = 1;
            name = "ESP";
            start = "1M";
            end = "128M";
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
            # Removed incorrect 'type = "disk"' here (not needed for partitions)
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/" = {
                  mountpoint = "/";
                  mountOptions = [ "compress=zstd" "noatime" ];
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
    };
    zpool.zstorage = {  # Moved zpool inside disko.devices
      type = "zpool";
      datasets = {
        storage = {
          type = "zfs_fs";
          mountpoint = "/storage";
          options = {
            compression = "zstd";
            atime = "off";
          };
        };
      };
    };
  };
}
