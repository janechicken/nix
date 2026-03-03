{ config, lib, ... }:

{
  services.syncthing = {
    enable = true;
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      gui = {
        user = "admin";
        password = "admin";
      };
      devices = {
        "phone" = {
          id = "ZGE6ZIT-632YYAI-CJFGW4Z-VQQYQWI-XQ5BIIP-2N6OWRX-FOOZINA-AMPD6QC";
        };
      };
      folders = {
        "sync" = {
          path = "${config.home.homeDirectory}/sync";
          devices = [ "phone" ];
          ignorePerms = true;
        };
      };
    };
  };
}
