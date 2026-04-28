{
  description = "A set of opinionated system information fetchers written in Zig, for use in status bars";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    {
      nixpkgs,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      formatter.${system} = pkgs.nixfmt-tree;
      packages.${system}.zitrus = pkgs.stdenv.mkDerivation {
        pname = "zitrus";
        version = "1.0.0";
        src = ./.;
        buildInputs = with pkgs; [ zig libpulseaudio ];
        buildPhase = "zig build -Doptimize=ReleaseSafe -p $out";
        installPhase = "";
      };
    };
}
