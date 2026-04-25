{
  description = "janes nix configs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcord = { url = "github:FlameFlag/nixcord"; };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-alien = { url = "github:thiagokokada/nix-alien"; };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, firefox-addons, nixcord
    , disko, nix-alien, sops-nix, ... }:
    let
      overlayFiles = import ./overlays/default.nix;
      overlay = nixpkgs.lib.composeManyExtensions (map import overlayFiles);
      # For home-manager, pkgs must already have the overlay applied
      pkgsWithOverlay = nixpkgs.legacyPackages.x86_64-linux.extend overlay;
    in
    {
      # nh os switch .
      nixosConfigurations = {
        jane-pc = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [ ./hosts/jane-pc/configuration.nix ];
        };
        jane-laptop = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [ ./hosts/jane-laptop/configuration.nix ];
        };
      };

      # nh home switch .
      homeConfigurations = {
        "jane@jane-pc" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsWithOverlay;
          extraSpecialArgs = { inherit inputs; };
          modules = [ ./hosts/jane-pc/home.nix ];
        };
        "jane@jane-laptop" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsWithOverlay;
          extraSpecialArgs = { inherit inputs; };
          modules = [ ./hosts/jane-laptop/home.nix ];
        };
      };
    };
}
