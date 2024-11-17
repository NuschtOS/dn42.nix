{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        # "aarch64-linux"
      ];

    in
    {
      nixosModules = rec {
        dn42 = {
          imports = [ ./modules ];
          nixpkgs.overlays = [ self.overlays.default ];
          _module.args = { inherit (self) libDn42; };
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

      packages = builtins.listToAttrs (map
        (system: {
          name = system;
          value = {
            dn42-roagen = import ./pkgs/dn42-roagen {
              pkgs = nixpkgs.legacyPackages.${system};
            };
          };
        })
        systems);

      overlays = rec {
        dn42 = _: prev: {
          dn42-roagen = import ./pkgs/dn42-roagen {
            pkgs = prev;
          };
        };
        default = dn42;
      };

      libDn42 = {
        inherit (import ./lib/dn42.nix { inherit (nixpkgs) lib; }) mkPeerV4 mkPeerV6 mkCollector6;
      };
    };
}
