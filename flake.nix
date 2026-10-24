{
  description = "A set of opinionated system information fetchers written in Zig, for use in status bars";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    zon2nix.url = "github:jcollie/zon2nix";
    zon2nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      zon2nix,
      self,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      formatter.${system} = pkgs.nixfmt-tree;
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          # No zls 0.17 in nixpkgs yet
          zon2nix.outputs.packages.${system}.zon2nix
        ];
        inputsFrom = [ self.packages.${system}.default ];
      };
      packages.${system}.default = pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "zitrus";
        version = "1.0.0";
        src = ./.;
        nativeBuildInputs = with pkgs; [
          zig_0_17
          libpulseaudio
        ];
        zigBuildFlags = [
          "--system"
          "${pkgs.callPackage ./build.zig.zon.nix { }}"
        ];
        zigCheckFlags = finalAttrs.zigBuildFlags;
      });
    };
}
