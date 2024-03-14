{ config, lib, ... }:
let
  cfg = config.networking.dn42;
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = 0 == (builtins.length (builtins.filter (conf: (!conf.extendedNextHop && (conf.addr.v4 == null || conf.srcAddr.v4 == null))) (builtins.attrValues cfg.peers)));
        message = "dn42.nix: IPv4 addresses are required, consider using extended next hop.";
      }
      {
        assertion = 0 == (builtins.length (builtins.filter (conf: (conf.extendedNextHop && (conf.addr.v4 != null || conf.srcAddr.v4 != null))) (builtins.attrValues cfg.peers)));
        message = "dn42.nix: IPv4 addresses are disallowed, consider not using extended next hop.";
      }
    ];

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

        function is_self_net_v4() -> bool {
          return net ~ [${builtins.concatStringsSep ", " cfg.nets.v4}];
        }

        function is_self_net_v6() -> bool {
          return net ~ [${builtins.concatStringsSep ", " cfg.nets.v6}];
        }

        function is_valid_network_v4() -> bool {
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
            ${lib.concatMapStrings (net: ''
              route ${net} reject;
            '') cfg.nets.v4}

            ipv4 {
                import all;
                export none;
            };
        }

        protocol static {
            ${lib.concatMapStrings (net: ''
              route ${net} reject;
            '') cfg.nets.v6}

            ipv6 {
                import all;
                export none;
            };
        }

        template bgp dnpeers {
          local as ${builtins.toString cfg.as};
          path metric 1;

          graceful restart on;
          long lived graceful restart on;
          interpret communities on;
          prefer older on;

          ipv4 {
            import filter {
              if is_valid_network_v4() && !is_self_net_v4() then {
                /*if (roa_check(dn42_roa, net, bgp_path.last) != ROA_VALID) then {
                  # Reject when unknown or invalid according to ROA
                  print "[dn42] ROA check failed for ", net, " ASN ", bgp_path.last;
                  reject;
                } else*/ accept;
              } else reject;
            };

            export filter { if is_valid_network_v4() && source ~ [RTS_STATIC, RTS_BGP] then accept; else reject; };
            
            import limit 9000 action block;
            import table on;
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
            import table on;
          };
        }

        ${builtins.concatStringsSep "\n" (builtins.attrValues
          (builtins.mapAttrs
            (name: conf: ''              
              ${lib.optionalString (!conf.extendedNextHop) ''
                protocol bgp ${name}_4 from dnpeers {
                  neighbor ${conf.addr.v4} as ${builtins.toString conf.as};
                  source address ${conf.srcAddr.v4};
                }
              ''}

              protocol bgp ${name}_6 from dnpeers {
                ${lib.optionalString conf.extendedNextHop ''
                  enable extended messages on;

                  ipv4 {
                    extended next hop on;    
                  };
                ''}
                
                neighbor ${conf.addr.v6}%'${conf.interface}' as ${builtins.toString conf.as};
                source address ${conf.srcAddr.v6};
              }
            '')
          cfg.peers))}
      '';
    };
  };
}
