{ config, lib, ... }:
let
  cfg = config.networking.dn42;
in
{
  imports = [
    ./firewall.nix
    ./bird2.nix
    ./stayrtr.nix
  ];

  options.networking.dn42 = {
    enable = lib.mkEnableOption "dn42 integration";

    routerId = lib.mkOption {
      type = lib.types.str;
      description = "32bit router identifier.";
      default = cfg.addr.v4;
    };

    as = lib.mkOption {
      type = lib.types.int;
      description = "Autonomous System Number";
    };

    geo = lib.mkOption {
      type = lib.types.int;
      description = "Geo code as defined in <https://dn42.net/howto/BGP-communities.md#region>.";
    };

    country = lib.mkOption {
      type = lib.types.int;
      description = "Country code vaguely based on ISO-3166-1 as defined in <https://dn42.net/howto/BGP-communities.md#country> See <https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes> for a list.";
    };

    blockedAs = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      description = "List of blocked AS numbers.";
    };

    collector.enable = lib.mkEnableOption "Enable route collector";

    addr = {
      v4 = lib.mkOption {
        type = lib.types.str;
        description = "Primary IPv4 address";
      };

      v6 = lib.mkOption {
        type = lib.types.str;
        description = "Primary IPv6 address";
      };
    };

    nets = {
      v4 = lib.mkOption {
        type = with lib.types; listOf str;
        description = "Own IPv4 networks, list of CIDR";
      };

      v6 = lib.mkOption {
        type = with lib.types; listOf str;
        description = "Own IPv6 networks, list of CIDR";
      };
    };

    peers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          as = lib.mkOption {
            type = lib.types.int;
            description = "Autonomous System number of the peer.";
          };

          extendedNextHop = lib.mkOption {
            type = lib.types.bool;
            description = "If extended next-hop should be used. Creating IPv4 routes using an IPv6 next-hop address.";
            default = false;
          };

          latency = lib.mkOption {
            type = lib.types.int;
            description = "Latency magic number of immeadiate link as described in <https://dn42.net/howto/BGP-communities#bgp-community-criteria>.";
          };

          bandwidth = lib.mkOption {
            type = lib.types.int;
            description = "Bandwith magic number between the peers as described in <https://dn42.net/howto/BGP-communities#bgp-community-criteria>.";
          };

          crypto = lib.mkOption {
            type = lib.types.int;
            description = "Encryption magic number as described in <https://dn42.net/howto/BGP-communities#bgp-community-criteria>";
          };

          transit = lib.mkOption {
            type = lib.types.bool;
            description = "Whether to provide a full table or not. Note: This option must be either true or false for all peers.";
          };

          addr = {
            v4 = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              description = "IPv4 address of the peer.";
              default = null;
            };

            v6 = lib.mkOption {
              type = lib.types.str;
              description = "IPv6 address of the peer.";
            };
          };

          srcAddr = {
            v4 = lib.mkOption {
              type = with lib.types; nullOr str;
              description = "Local IPv4 address to use for BGP.";
              default = null;
            };

            v6 = lib.mkOption {
              type = with lib.types; nullOr str;
              description = "Local IPv6 address to use for BGP.";
            };
          };

          interface = lib.mkOption {
            type = lib.types.str;
            description = "Interface name of the peer.";
          };
        };
      });
    };

    vrf = {
      name = lib.mkOption {
        type = lib.types.strMatching "^[A-Za-z0-9_]+$";
        default = "vrf0";
        description = "Name of the vrf to use. May differ from the kernel vrf name.";
      };
      table = lib.mkOption {
        type = with lib.types; nullOr int;
        default = null;
        description = "Kernel routing table number to use.";
      };
    };
  };
}
