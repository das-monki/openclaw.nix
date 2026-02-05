{
  description = "My Openclaw configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management (choose one)
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Openclaw module
    openclaw-nix = {
      url = "github:YOURUSERNAME/openclaw.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      agenix,
      openclaw-nix,
      ...
    }:
    let
      system = "x86_64-linux"; # Change to your system
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # Standalone Home Manager configuration
      homeConfigurations."youruser" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          agenix.homeManagerModules.default
          openclaw-nix.homeManagerModules.default

          ./home.nix
        ];
      };

      # Or as part of a NixOS configuration
      nixosConfigurations.yourhost = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          agenix.nixosModules.default
          home-manager.nixosModules.home-manager

          {
            home-manager.users.youruser = {
              imports = [
                openclaw-nix.homeManagerModules.default
                ./home.nix
              ];
            };
          }
        ];
      };
    };
}
