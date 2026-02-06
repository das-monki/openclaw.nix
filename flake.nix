{
  description = "Openclaw - Personal AI assistant for NixOS/Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      llm-agents,
      systems,
    }:
    let
      eachSystem = nixpkgs.lib.genAttrs (import systems);

      # Package for each system
      openclawFor = system: llm-agents.packages.${system}.openclaw;
    in
    {
      # ============ MODULES ============

      homeManagerModules.openclaw = import ./modules/home-manager {
        inherit llm-agents;
        configSchemaPackage = ./packages/config-schema.nix;
      };
      homeManagerModules.default = self.homeManagerModules.openclaw;

      # NixOS system-level module (uses User= directive)
      nixosModules.openclaw = import ./modules/nixos {
        inherit llm-agents;
        configSchemaPackage = ./packages/config-schema.nix;
      };
      nixosModules.default = self.nixosModules.openclaw;

      # Darwin support via Home Manager
      darwinModules.openclaw = self.homeManagerModules.openclaw;
      darwinModules.default = self.darwinModules.openclaw;

      # ============ PACKAGES ============

      packages = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          openclaw = openclawFor system;
        in
        {
          inherit openclaw;
          default = openclaw;

          openclaw-config-schema = pkgs.callPackage ./packages/config-schema.nix {
            inherit openclaw;
          };
        }
      );

      # ============ OVERLAYS ============

      overlays.default = final: prev: {
        openclaw = openclawFor prev.stdenv.hostPlatform.system;
      };

      # ============ CHECKS ============

      checks = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          isLinux = pkgs.stdenv.isLinux;
        in
        {
          # Schema validation (basic)
          config-schema = pkgs.callPackage ./checks/config-schema.nix {
            configSchema = self.packages.${system}.openclaw-config-schema;
          };

          # Schema validation with channel configs (tests nested defaults)
          config-schema-channels = pkgs.callPackage ./checks/config-schema-channels.nix {
            configSchema = self.packages.${system}.openclaw-config-schema;
          };

          # Home Manager module evaluation
          hm-module-eval = import ./checks/module-eval.nix {
            inherit pkgs home-manager;
            openclawModule = self.homeManagerModules.openclaw;
          };

          # NixOS module evaluation (Linux only - uses lib.nixosSystem)
          nixos-module-eval = import ./checks/nixos-module-eval.nix {
            inherit pkgs nixpkgs;
            lib = nixpkgs.lib;
            nixosModule = self.nixosModules.openclaw;
          };
        }
        // nixpkgs.lib.optionalAttrs isLinux {
          # NixOS VM integration test (Linux only, requires KVM)
          nixos-vm-test = import ./checks/nixos-vm-test.nix {
            inherit pkgs;
            nixosModule = self.nixosModules.openclaw;
          };
        }
      );

      # ============ TEMPLATES ============

      templates.default = {
        path = ./templates/starter;
        description = "Starter configuration for openclaw.nix";
      };

      # ============ FORMATTER ============

      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
