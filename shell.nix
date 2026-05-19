{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = with pkgs.buildPackages; [
    git
    erlang
    rebar3
    erlang-language-platform
    erlfmt
    # opam
    go
    gotools
  ];
}