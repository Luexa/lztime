{
  description = "Flake for lztime development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig = {
      url = "github:bandithedoge/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, zig }: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  in
    flake-utils.lib.eachSystem systems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      packages.zig = zig.packages.${system}.master;
      packages.zls = packages.zig.zls;
    in {
      devShells.default = pkgs.mkShell {
        nativeBuildInputs = [
          packages.zig
          packages.zls
        ];
      };
    });
}
