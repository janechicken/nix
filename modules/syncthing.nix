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
          id = "2IXDMGV-3L364EY-ITQUK4N-763PTIW-VEBJ6MZ-HA6OSI3-U4CGWNW-LHMP6A6";
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
