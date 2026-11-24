{ config, lib, pkgs, ... }:

let
  jane = config.users.users.jane;
in
{
  # Sops-nix secret management
  sops.age.keyFile = "/var/lib/sops-nix/keys.txt";
  # No ssh host key is imported as an age identity; the default path
  # /etc/ssh/ssh_host_ed25519_key does not exist here and only warned.
  sops.age.sshKeyPaths = [ ];
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets."ssh_key" = {
    owner = config.users.users.jane.name;
    path = "${jane.home}/.ssh/id_rsa";
  };
  sops.secrets."ssh_pubkey" = {
    owner = config.users.users.jane.name;
    path = "${jane.home}/.ssh/id_rsa.pub";
  };
  sops.secrets."nanogpt_api_key" = {
    owner = config.users.users.jane.name;
  };
  sops.secrets."openrouter_api_key" = {
    owner = config.users.users.jane.name;
  };
  sops.secrets."refuseless_api_key" = {
    owner = config.users.users.jane.name;
  };
  # sops.secrets."gpg_key" = { # uncomment when needed
  #   owner = config.users.users.jane.name;
  # };
  # TODO: declare `refuseless_api_key` here only after it is added to
  # secrets/secrets.yaml — a declared-but-missing secret makes
  # sops-install-secrets fail during activation. modules/pi.nix already reads
  # /run/secrets/refuseless_api_key if it appears.

  # sops-install-secrets creates a missing parent directory as root, which left
  # ~/.ssh owned by root and made ssh reject id_rsa. Create it as jane before
  # setupSecrets writes the keys there.
  system.activationScripts.prepareJaneSsh = lib.stringAfter [ "users" ] ''
    install -d -o ${jane.name} -g ${jane.group} -m 0700 ${jane.home}/.ssh
    chown ${jane.name}:${jane.group} ${jane.home}/.ssh
    chmod 0700 ${jane.home}/.ssh
  '';
  system.activationScripts.setupSecrets.deps = [ "prepareJaneSsh" ];

  # Export the keys from shell init instead of `environment.sessionVariables`:
  # there the `$(cat ...)` runs unguarded on every login, so a secret that has
  # not been provisioned yet leaves an empty variable and prints a `cat` error.
  environment.extraInit = ''
    _sops_env() {
      if [ -r "/run/secrets/$1" ]; then
        export "$2=$(cat "/run/secrets/$1")"
      fi
    }
    _sops_env cheapcompute_api_key CHEAPCOMPUTE_API_KEY
    _sops_env nanogpt_api_key NANOGPT_API_KEY
    _sops_env openrouter_api_key OPENROUTER_API_KEY
    _sops_env merge_api_key MERGE_GATEWAY_API_KEY
    # Zed's [OI]-compatible edit prediction endpoint is DeepSeek.
    if [ -n "''${DEEPSEEK_API_KEY:-}" ]; then
      export ZED_OPEN_AI_COMPATIBLE_EDIT_PREDICTION_API_KEY="$DEEPSEEK_API_KEY"
    fi
    unset -f _sops_env
  '';
}
