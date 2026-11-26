{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
{

  security.rtkit.enable = true;
  # Dynamic quantum instead of a pinned 128 frames: a fixed 128 makes every
  # graph re-run 375 times/s (48000/128) on an idle desktop, and each run wakes
  # the CPU out of idle. 1024 as the default is 46.9 wakeups/s (8x fewer) for
  # browsing/calls/video, which no one can hear the difference in. The bounds
  # keep pro audio intact: a JACK/PipeWire client asking for 128 frames
  # (REAPER via `pw-jack` / `PIPEWIRE_LATENCY=128/48000`) still gets exactly
  # 128, because `min-quantum` stays at 128 and the client-requested latency
  # drives the graph quantum (nothing sets `node.force-quantum`).
  services.pipewire.extraConfig.pipewire."92-dynamic-quantum" = {
    "context.properties" = {
      "default.clock.rate" = 48000;
      "default.clock.quantum" = 1024;
      "default.clock.min-quantum" = 128;
      "default.clock.max-quantum" = 2048;
    };
  };
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = pkgs.stdenv.hostPlatform.isx86_64;
    jack.enable = true;
  };

  # Keep Bluetooth headphones permanently on A2DP: dropping the HSP/HFP roles
  # removes the low-quality headset/microphone profiles altogether, and
  # disabling the autoswitch stops WirePlumber from moving the device to
  # headset mode whenever an application starts recording. A2DP is still
  # auto-connected, so headsets link up cleanly on boot.
  services.pipewire.wireplumber.extraConfig."51-bluez-a2dp-only" = {
    "wireplumber.settings" = {
      "bluetooth.autoswitch-to-headset-profile" = false;
    };
    "monitor.bluez.properties" = {
      "bluez5.roles" = [
        "a2dp_sink"
        "a2dp_source"
      ];
      "bluez5.hfphsp-backend" = "none";
    };
    "monitor.bluez.rules" = [
      {
        matches = [
          { "device.name" = "~bluez_card.*"; }
        ];
        actions.update-props."bluez5.auto-connect" = [ "a2dp_sink" ];
      }
    ];
  };
  environment.variables = {
    LV2_PATH = "$HOME/.lv2:$HOME/.nix-profile/lib/lv2:/run/current-system/sw/lib/lv2";
  };
  security.pam.loginLimits = [
    {
      domain = "@audio";
      item = "memlock";
      type = "-";
      value = "unlimited";
    }
    {
      domain = "@audio";
      item = "rtprio";
      type = "-";
      value = "99";
    }
    {
      domain = "@audio";
      item = "nofile";
      type = "soft";
      value = "99999";
    }
    {
      domain = "@audio";
      item = "nofile";
      type = "hard";
      value = "99999";
    }
  ];
}
