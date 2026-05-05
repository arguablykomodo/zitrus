{
  description = "A set of opinionated system information fetchers written in Zig, for use in status bars";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    zon2nix.url = "github:Sh4pe/zon2nix?ref=update-zig-0-16";
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
          zls
          zon2nix.outputs.packages.${system}.default
        ];
        inputsFrom = [ self.packages.${system}.default ];
      };
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        pname = "zitrus";
        version = "1.0.0";
        src = ./.;
        nativeBuildInputs = with pkgs; [
          zig
          libpulseaudio
        ];
        postPatch = ''
          ln -s ${pkgs.callPackage ./deps.nix { }} zig-pkg
        '';
      };
    };
}
