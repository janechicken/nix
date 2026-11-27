# SSH client config. The key material itself is provisioned by sops-nix in
# secrets/sops-nix.nix:
#
#   ~/.ssh/id_rsa      YubiKey resident key (sk-ssh-ed25519@openssh.com)
#   ~/.ssh/id_ed25519  software ed25519 key
#
# OpenSSH's built-in default identity list already contains both filenames, but
# it tries `id_rsa` first, so every connection would wait for a YubiKey touch
# even when the software key would do. Listing them explicitly puts the software
# key first and keeps the YubiKey as the fallback. `IdentitiesOnly` is
# deliberately left off, so keys offered by an agent (including a forwarded one)
# still work.
{ ... }:

{
  programs.ssh = {
    enable = true;
    # home-manager's own defaults add a `Host *` block with unrelated agent and
    # known-hosts tweaks; only the identity order is wanted here.
    enableDefaultConfig = false;
    matchBlocks."*".identityFile = [
      "~/.ssh/id_ed25519"
      "~/.ssh/id_rsa"
    ];
  };
}
