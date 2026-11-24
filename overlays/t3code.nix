final: prev: {
  # Local bump of the nixpkgs packaging in pkgs/t3code/ (upstream 0.1.11 is
  # ahead of nixos-unstable, which is still on 0.1.8). Only `t3code` is
  # replaced; nixpkgs stays pinned so linux-mahua / mesa-mahua keep their
  # cache.nixos.org hits.
  t3code = final.callPackage ../pkgs/t3code/package.nix { };
}
