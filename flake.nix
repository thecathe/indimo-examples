{
  description = "Nix flake for development";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
    {

      devShells.x86_64-linux.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          git
          erlang
          rebar3
          erlang-language-platform
          erlfmt
          opam
          go
          gotools
        ];
      };

    };
}
