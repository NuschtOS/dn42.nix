{
  inputs = {
    bird = {
      url = "github:NuschtOS/bird.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, bird, ... }:
    let
      systems = [
        "x86_64-linux"
        # "aarch64-linux"
      ];

    in
    {
      nixosModules = rec {
        dn42 = {
          imports = [ bird.nixosModules.bird ./modules ];
        };
        default = dn42;
      };

      checks = builtins.listToAttrs (map
        (system: {
          name = system;
          value = {
            two-peers = import ./checks/two-peers.nix {
              inherit self;
              pkgs = nixpkgs.legacyPackages.${system};
            };
            extended-next-hop = import ./checks/extended-next-hop.nix {
              inherit self;
              pkgs = nixpkgs.legacyPackages.${system};
            };
          };
        })
        systems);
    };
}
