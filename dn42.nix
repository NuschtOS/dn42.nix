{ config, lib, ... }:
let
  cfg = config.networking.dn42;
in
{
  options.networking.dn42 = {
    enable = lib.mkEnableOption "Whether to enable dn42 integration.";

    routerId = lib.mkOption {
      type = lib.types.str;
      description = "32bit router identifier.";
    };

    as = lib.mkOption {
      type = lib.types.int;
      description = "Autonomous Systemd number of yourself.";
    };

    addr = {
      v4 = lib.mkOption {
        type = lib.types.str;
        description = "IPv4 address of yourself.";
      };

      v6 = lib.mkOption {
        type = lib.types.str;
        description = "IPv6 address of yourself.";
      };
    };

    net = {
      v4 = lib.mkOption {
        type = lib.types.str;
        description = "own IPv4 net";
      };

      v6 = lib.mkOption {
        type = lib.types.str;
        description = "own IPv6 net";
      };
    };

    peers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ config, name, ... }: {
        options = {
          as = lib.mkOption {
            type = lib.types.int;
            description = "Autonomous Systemd number of the peer.";
          };

          interface = lib.mkOption {
            type = lib.types.str;
            description = "Interface name of the peer.";
          };

          addr = {
            v4 = lib.mkOption {
              type = lib.types.str;
              description = "IPv4 address of the peer.";
            };

            v6 = lib.mkOption {
              type = lib.types.str;
              description = "IPv6 address of the peer.";
            };
          };
        };
      }));
    };
  };

  config = lib.mkIf cfg.enable {

    services.bird2 = {
      enable = true;
      config = ''
        router id ${cfg.routerId};

        protocol device {
            scan time 10;
        }

        /*
         *  Utility functions
         */

        function is_self_net() -> bool {
          return net ~ ${cfg.net.v4};
        }

        function is_self_net_v6() -> bool {
          return net ~ ${cfg.net.v6};
        }

        function is_valid_network() -> bool {
          return net ~ [
            172.20.0.0/14{21,29}, # dn42
            172.20.0.0/24{28,32}, # dn42 Anycast
            172.21.0.0/24{28,32}, # dn42 Anycast
            172.22.0.0/24{28,32}, # dn42 Anycast
            172.23.0.0/24{28,32}, # dn42 Anycast
            172.31.0.0/16+,       # ChaosVPN
            10.100.0.0/14+,       # ChaosVPN
            10.127.0.0/16{16,32}, # neonetwork
            10.0.0.0/8{15,24}     # Freifunk.net
          ];
        }

        /*
        roa4 table dn42_roa;
        roa6 table dn42_roa_v6;

        protocol static {
            roa4 { table dn42_roa; };
            include "/etc/bird/roa_dn42.conf";
        };

        protocol static {
            roa6 { table dn42_roa_v6; };
            include "/etc/bird/roa_dn42_v6.conf";
        };
        */

        function is_valid_network_v6() -> bool {
          return net ~ [
            fd00::/8{44,64} # ULA address space as per RFC 4193
          ];
        }

        protocol kernel {
            scan time 20;

            ipv4 {
                import none;
                export filter {
                    if source = RTS_STATIC then reject;
                    krt_prefsrc = ${cfg.addr.v4};
                    accept;
                };
            };
        }

        protocol kernel {
            scan time 20;

            ipv6 {
                import none;
                export filter {
                    if source = RTS_STATIC then reject;
                    krt_prefsrc = ${cfg.addr.v6};
                    accept;
                };
            };
        };

        protocol static {
            route ${cfg.net.v4} reject;

            ipv4 {
                import all;
                export none;
            };
        }

        protocol static {
            route ${cfg.net.v6} reject;

            ipv6 {
                import all;
                export none;
            };
        }

        template bgp dnpeers {
            local as ${builtins.toString cfg.as};
            path metric 1;

            ipv4 {
                import filter {
                  if is_valid_network() && !is_self_net() then {
                    /*if (roa_check(dn42_roa, net, bgp_path.last) != ROA_VALID) then {
                      # Reject when unknown or invalid according to ROA
                      print "[dn42] ROA check failed for ", net, " ASN ", bgp_path.last;
                      reject;
                    } else*/ accept;
                  } else reject;
                };

                export filter { if is_valid_network() && source ~ [RTS_STATIC, RTS_BGP] then accept; else reject; };
                import limit 9000 action block;
            };

            ipv6 {   
                import filter {
                  if is_valid_network_v6() && !is_self_net_v6() then {
                    /*if (roa_check(dn42_roa_v6, net, bgp_path.last) != ROA_VALID) then {
                      # Reject when unknown or invalid according to ROA
                      print "[dn42] ROA check failed for ", net, " ASN ", bgp_path.last;
                      reject;
                    } else*/ accept;
                  } else reject;
                };
                export filter { if is_valid_network_v6() && source ~ [RTS_STATIC, RTS_BGP] then accept; else reject; };
                import limit 9000 action block; 
            };
        }

        ${builtins.concatStringsSep "\n" (builtins.attrValues
          (builtins.mapAttrs
            (name: conf: ''
              protocol bgp ${name}_4 from dnpeers {
                neighbor ${conf.addr.v4} as ${builtins.toString conf.asn};
              }
              
              protocol bgp ${name}_6 from dnpeers {
                neighbor ${conf.addr.v6}%${conf.interface} as ${builtins.toString conf.asn};
              }
            '')
          cfg.peers))}
      '';
    };
  };
}
