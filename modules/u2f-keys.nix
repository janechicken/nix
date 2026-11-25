# pam_u2f credential mapping. The PAM side lives in modules/fido.nix; this only
# provisions the authfile that pam_u2f reads, so the registration is part of the
# flake instead of existing solely in the home directory.
#
# Both hosts deliberately share one registration: modules/fido.nix pins a
# host-independent relying party ID (`origin`/`appid` = `pam://nixos-jane`), so
# the same credential unlocks `sudo` and `hyprlock` on jane-pc and yogabook.
#
# Safe to keep in a public repo. The authfile holds only the *public* half of the
# WebAuthn registration - key handle, public key, COSE algorithm (`es256`) and
# the `+presence` flag. The private key never leaves the YubiKey, so this file
# cannot authenticate anything on its own; it only tells pam_u2f which credential
# to challenge. Re-register with:
#
#   pamu2fcfg -o pam://nixos-jane -i pam://nixos-jane
#
# and paste the single printed line below.
{
  ...
}:

let
  # Format: <username>:<KeyHandle>,<UserKey>,<CoseType>,<Options>
  registration = "jane:yvqbFuFOMBLaxaLSnTUaPmd/a+LaMsUCGA0SHUbjbMJ/2L6QM6C7gmjSEpqajA4NtzJhcW2OyG9IH9l4/oHg7g==,bJhDgOvvh3lYSfDiwH4YAgJk896kqME/HFxBkWoxehSn6xRQnt98jIicq7bvX4S46Y8CVzTIXLoy4ZU3JmIPiw==,es256,+presence";
in
{
  # `pam_u2f` defaults to $XDG_CONFIG_HOME/Yubico/u2f_keys (or
  # $HOME/.config/Yubico/u2f_keys), which is where modules/fido.nix points its
  # explicit `authfile`. Kept byte-identical to pamu2fcfg's output: one line, no
  # trailing newline.
  xdg.configFile."Yubico/u2f_keys".text = registration;
}
