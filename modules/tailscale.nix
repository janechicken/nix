# Tailscale — WireGuard mesh VPN client on both hosts.
#
# Client-only on purpose: no auth key is baked in (run `tailscale up` once per
# machine) and no autoconnect unit is enabled, so boot never blocks on the
# control plane. `useRoutingFeatures = "client"` is what lets this node use an
# exit node / subnet router: it sets `networking.firewall.checkReversePath` to
# "loose", since replies from an exit node do not return via tailscale0.
#
# Both hosts currently set `networking.firewall.enable = false`, so
# `openFirewall` and `trustedInterfaces` are declarative only today; they keep
# direct (non-DERP) peer connections and tailnet traffic working if the
# firewall is ever turned back on.
{
  services.tailscale = {
    enable = true;
    # UDP 41641 for direct peer-to-peer connections (falls back to DERP relays).
    openFirewall = true;
    useRoutingFeatures = "client";
  };

  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
