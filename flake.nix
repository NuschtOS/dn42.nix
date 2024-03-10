{
  outputs = { ... }: {
    nixosModules = rec {
      dn42 = import ./dn42.nix;
      default = dn42;
    };
  };
}
