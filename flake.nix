{
  description = "Stand-in for the cluster policy chart, checked offline with chart-checks";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    # nixos-26.05 (Yarara) @ 2026-08-06, same pin as the diene workspace template
    nixpkgs-2605.url = "github:NixOS/nixpkgs/445d861c6d31b4af0c79d8d4be2331f762a361d7";
    # chart-checks: the same tool the template repos use; atomipkgs floats on the v5 major line
    atomipkgs.url = "github:AtomiCloud/nix-registry/v5";
  };

  outputs =
    {
      flake-utils,
      nixpkgs-2605,
      atomipkgs,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs-2605.legacyPackages.${system};
        atomi = atomipkgs.packages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            atomi.chart-checks
            pkgs.git
          ];
        };
      }
    );
}
