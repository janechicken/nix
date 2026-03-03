{ config, lib, ... }:

{
  services.syncthing = {
    enable = true;
    user = config.home.username;
    dataDir = config.home.homeDirectory;
    configDir = "${config.home.homeDirectory}/.config/syncthing";
    openDefaultPorts = true;
    settings.gui = {
      user = "admin";
      password = "admin";
    };
    settings.devices = {
      "phone" = {
        id = "ZGE6ZIT-632YYAI-CJFGW4Z-VQQYQWI-XQ5BIIP-2N6OWRX-FOOZINA-AMPD6QC";
      };
    };
    settings.folders = {
      "sync" = {
        path = "${config.home.homeDirectory}/sync";
        devices = [ "phone" ];
        ignorePerms = true;
      };
    };
  };
}
