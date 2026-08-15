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
    nixcord = {
      url = "github:FlameFlag/nixcord";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-alien = {
      url = "github:thiagokokada/nix-alien";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixwrap.url = "github:rti/nixwrap";
    renix.url = "github:ironfisto/renix?dir=main";
    ctf-skills = {
      url = "github:ljagiello/ctf-skills";
      flake = false;
    };
    agent-skills-nix = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cybersec-skills = {
      url = "github:mukul975/Anthropic-Cybersecurity-Skills";
      flake = false;
    };
    rust-skills = {
      url = "github:leonardomso/rust-skills";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      firefox-addons,
      nixcord,
      disko,
      nix-alien,
      sops-nix,
      nixwrap,
      ...
    }:
    let
      overlayFiles = import ./overlays/default.nix;
      overlay = nixpkgs.lib.composeManyExtensions (map import overlayFiles);
      # For home-manager, pkgs must already have the overlay applied
      # pkgs with the overlay pre-applied, per system. NixOS configs apply the
      # overlay via nixpkgs.overlays; home-manager needs it baked into pkgs.
      pkgsFor = system: nixpkgs.legacyPackages.${system}.extend overlay;
      mkNixos =
        system: host:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/${host}/configuration.nix
            { nixpkgs.overlays = [ overlay ]; }
          ];
        };
      mkHome =
        system: host:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor system;
          extraSpecialArgs = { inherit inputs; };
          modules = [ ./hosts/${host}/home.nix ];
        };
    in
    {
      # nh os switch .
      nixosConfigurations = {
        jane-pc = mkNixos "x86_64-linux" "jane-pc";
      };

      # nh home switch .
      homeConfigurations = {
        "jane@jane-pc" = mkHome "x86_64-linux" "jane-pc";
      };
    };
}
