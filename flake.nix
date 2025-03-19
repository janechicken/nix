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
    nvchad-starter = {
      url = "./dotfiles/nvim";
      flake = false;
    };
    nvchad4nix = {
      url = "github:nix-community/nix4nvchad";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nvchad-starter.follows = "nvchad-starter";
    };
    yeetmouse = {
    url = "github:AndyFilter/YeetMouse/driver/experimental/?dir=nix";
    inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcord = {
      url = "github:kaylorben/nixcord";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, firefox-addons, nvchad4nix, fenix, yeetmouse, nixcord, ...}: {
         # nh os switch .
         nixosConfigurations = {
	   octo-pc = nixpkgs.lib.nixosSystem {
       system = "x86_64-linux";
	     specialArgs = {inherit inputs;};
	     modules = [ ./hosts/octo-pc/configuration.nix ];
	   };
	 };

	 # nh home switch .
	 homeConfigurations = {
	   "octo@octo-pc" = home-manager.lib.homeManagerConfiguration {
	     pkgs = nixpkgs.legacyPackages.x86_64-linux;
	     extraSpecialArgs = {inherit inputs;};
	     modules = [ ./hosts/octo-pc/home.nix ];
	   };
	 };
  };
}
