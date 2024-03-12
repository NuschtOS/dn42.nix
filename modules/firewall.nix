{ config, lib, ... }:
let
  enable = config.networking.dn42.enable && config.networking.firewall.enable;

in
{
  # Allow BGP on peering interfaces
  # TODO: these should actually only additionally filter for peer's
  # addresses, but there is no NixOS option for that.
  networking.firewall.interfaces = lib.mkIf enable (
    builtins.listToAttrs (
      map (interface: {
        name = interface;
        value.allowedTCPPorts = [
          # BGP
          179
        ];
      }) (
        map ({ interface, ... }: interface) (
          builtins.attrValues config.networking.dn42.peers
        )
      )
    )
  );
}
