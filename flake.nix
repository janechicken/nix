{
  description = "octos nix configs";

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
    yeetmouse = {
      url = "github:AndyFilter/YeetMouse/driver/experimental/?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcord = { url = "github:kaylorben/nixcord"; };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, firefox-addons,  fenix, yeetmouse, nixcord, disko, ... }: {
      # nh os switch .
      nixosConfigurations = {
        octo-pc = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [ ./hosts/octo-pc/configuration.nix ];
        };

        omen = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [ ./hosts/omen/configuration.nix disko.nixosModules.disko ];
        };
      };

      # nh home switch .
      homeConfigurations = {
        "octo@octo-pc" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          extraSpecialArgs = { inherit inputs; };
          modules = [ ./hosts/octo-pc/home.nix ];
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
