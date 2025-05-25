{ config, inputs, pkgs, lib, ... }: {
  xdg.desktopEntries.cemu-obs = {
    name = "Cemu (OBS Capture)";
    exec = "obs-gamecapture ${pkgs.cemu}/bin/Cemu";
    icon = "cemu";
    comment = "Cemu Wii U Emulator with OBS capture";
    categories = [ "Game" "Emulator" ];
    mimeType = [ "application/x-cemu" ];
    startupNotify = false;
    # Hide the original if desired
    settings = { NoDisplay = "false"; };
  };

  home.packages = with pkgs; [ cemu ];
}
