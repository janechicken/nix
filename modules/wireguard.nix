{ config, pkgs, lib, ... }:

{
  networking.wireguard.interfaces = {
    wg0 = {
      ips = [ "10.100.0.1/24" ];
      listenPort = 51820;
      privateKeyFile = "/etc/wireguard/wg0.key";
      generatePrivateKeyFile = true;

      # Peers — remote devices that connect in
      peers = [
        {
          # Jane's phone (mobile data)
          publicKey = "1cYFjW/BR6eQ7NP8tA5vaqw3Hl8qGet098/65owQ7U4=";
          allowedIPs = [ "10.100.0.2/32" ];
        }
      ];
    };
  };

  environment.systemPackages = with pkgs; [ wireguard-tools ];
  networking.firewall.allowedUDPPorts = [ 51820 ];
}
