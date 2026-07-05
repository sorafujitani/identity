{
  description = "Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neovim-nightly = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.neovim-src.url = "github:neovim/neovim/v0.12.0";
    };
  };

  outputs = { nixpkgs, home-manager, neovim-nightly, ... }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [ "1password-cli" ];
        overlays = [
          neovim-nightly.overlays.default
          (_: prev: {
            direnv = prev.direnv.overrideAttrs (_: { doCheck = false; });
          })
        ];
      };
    in
    {
      homeConfigurations."fujitanisora" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
      };
    };
}
