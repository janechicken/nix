{
  description = "octos nix configs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sf-mono-liga-src = {
      url = "github:shaunsingh/SFMono-Nerd-Font-Ligaturized";
      flake = false;
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvchad-starter = {
      url = "path:./dotfiles/nvim";
      flake = false;
    };
    nvchad4nix = {
      url = "github:nix-community/nix4nvchad";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nvchad-starter.follows = "nvchad-starter";
    };
  };

  outputs = { self, nixpkgs, home-manager, sf-mono-liga-src, firefox-addons, nvchad4nix, ...} @inputs: let 
    inherit (self) outputs;
    in {
         # sudo nixos-rebuild switch --flake .#octo-pc
         nixosConfigurations = {
	   octo-pc = nixpkgs.lib.nixosSystem {
	     specialArgs = {inherit inputs outputs;};
	     modules = [ ./hosts/octo-pc/configuration.nix ];
	   };
	 };

	 # home-manager switch --flake .#octo@octo-pc
	 homeConfigurations = {
	   "octo@octo-pc" = home-manager.lib.homeManagerConfiguration {
	     pkgs = nixpkgs.legacyPackages.x86_64-linux;
	     extraSpecialArgs = {inherit inputs outputs;};
	     modules = [ ./hosts/octo-pc/home.nix ];
	   };
	 };
       };
}
