{ config, lib, ... }:
let
  cfg = config.networking.dn42;
in
{
  imports = [
    ./firewall.nix
    ./bird2.nix
  ];

  options.networking.dn42 = {
    enable = lib.mkEnableOption "Whether to enable dn42 integration.";

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
      description = "";
    };

    country = lib.mkOption {
      type = lib.types.int;
      description = "";
    };

    blockedAs = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      description = "";
    };

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
      type = lib.types.attrsOf (lib.types.submodule ({ config, name, ... }: {
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
            description = "";
          };

          bandwidth = lib.mkOption {
            type = lib.types.int;
            description = "";
          };

          crypto = lib.mkOption {
            type = lib.types.int;
            description = "";
          };

          transit = lib.mkOption {
            type = lib.types.bool;
            description = "";
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
      }));
    };
  };
}
