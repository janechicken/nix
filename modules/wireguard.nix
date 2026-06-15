{ config, pkgs, lib, ... }:

{
  networking.wireguard.interfaces = {
    wg0 = {
      ips = [ "10.100.0.1/24" ];
      listenPort = 51820;
      privateKeyFile = "/etc/wireguard/wg0.key";
      generatePrivateKeyFile = true;

      # Pi peers — add as each Pi gets set up:
      # {
      #   publicKey = "<Pi's public key>";
      #   allowedIPs = [ "10.100.0.2/32" ];
      # }
      peers = [ ];
    };
  };

  environment.systemPackages = with pkgs; [ wireguard-tools ];
  networking.firewall.allowedUDPPorts = [ 51820 ];
}
