{
  outputs = { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        # "aarch64-linux"
      ];

    in
    {
      nixosModules = rec {
        dn42 = import ./modules;
        default = dn42;
      };

      checks = builtins.listToAttrs (map
        (system: {
          name = system;
          value = {
            two-peers = import ./checks/two-peers.nix {
              pkgs = nixpkgs.legacyPackages.${system};
            };
            extended-next-hop = import ./checks/extended-next-hop.nix {
              pkgs = nixpkgs.legacyPackages.${system};
            };
          };
        })
        systems);
    };
}
