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
    nixcord = { url = "github:kaylorben/nixcord"; };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-alien = { url = "github:thiagokokada/nix-alien"; };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, firefox-addons, fenix, nixcord
    , disko, nix-alien, ... }: {
      # nh os switch .
      nixosConfigurations = {
        jane-pc = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [ ./hosts/jane-pc/configuration.nix ];
        };

        omen = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [ ./hosts/omen/configuration.nix disko.nixosModules.disko ];
        };
      };

      # nh home switch .
      homeConfigurations = {
        "jane@jane-pc" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          extraSpecialArgs = { inherit inputs; };
          modules = [ ./hosts/jane-pc/home.nix ];
        };
      };
      homeConfigurations = {
        "root@omen" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          extraSpecialArgs = { inherit inputs; };
          modules = [ ./hosts/omen/home.nix ];
        };
      };
    };
}
