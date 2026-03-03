{ config, lib, pkgs, ... }:

{
  # Sops-nix secret management
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets."openrouter_api_key" = {
    path = "/run/secrets/openrouter_api_key";
    mode = "0444";  # Readable by all users
  };

  # Set environment variable system-wide
  environment.sessionVariables = {
    OPENROUTER_API_KEY = "$(cat /run/secrets/openrouter_api_key)";
  };
}
