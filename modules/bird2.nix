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
        define OWNAS = ${toString cfg.as};
        define OWNIP = ${toString cfg.addr.v6};

        define BANDWIDTH = ${toString cfg.bandwidth};
        define REGION_GEO = ${toString cfg.geo};
        define REGION_COUNTRY = ${toString cfg.country};

        define ASN_BLACKLIST = [];

        function is_self_net_v4() -> bool {
          return net ~ [${builtins.concatStringsSep ", " cfg.nets.v4}];
        }

        function is_self_net_v6() -> bool {
          return net ~ [${builtins.concatStringsSep ", " cfg.nets.v6}];
        }

        function is_self_net() -> bool {
          return is_self_net_v4() || is_self_net_v6();
        }

        include "${../resources/community_filter.conf}";
        include "${../resources/filters.conf}";
      
        router id ${cfg.routerId};
        hostname "${config.networking.hostName}.${config.networking.domain}";

        protocol device {
            scan time 10;
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

          enforce first as on;
          graceful restart on;
          long lived graceful restart on;
          advertise hostname on;
          prefer older on;

          # defaults
          enable route refresh on;
          interpret communities on;
          default bgp_local_pref 100;
        }

        ${builtins.concatStringsSep "\n" (builtins.attrValues
          (builtins.mapAttrs
            (name: conf: ''              
              ${lib.optionalString (!conf.extendedNextHop) ''
                protocol bgp ${name}_4 from dnpeers {
                  neighbor ${conf.addr.v4} as ${builtins.toString conf.as};
                  source address ${conf.srcAddr.v4};

                  ipv4 {
                    import limit 9000 action block;
                    import table on;

                    import where dn_import_filter(${toString conf.latency}, ${toString conf.bandwidth}, ${toString conf.crypto});
                    export where dn_export_filter(${toString conf.latency}, ${toString conf.bandwidth}, ${toString conf.crypto});
                  };
                }
              ''}

              protocol bgp ${name}_6 from dnpeers {
                ${lib.optionalString conf.extendedNextHop ''
                  enable extended messages on;

                  ipv4 {
                    import limit 9000 action block;
                    import table on;
                    
                    extended next hop on;
                    import where dn_import_filter(${toString conf.latency}, ${toString conf.bandwidth}, ${toString conf.crypto});
                    export where dn_export_filter(${toString conf.latency}, ${toString conf.bandwidth}, ${toString conf.crypto});
                  };
                ''}

                ipv6 {
                  import limit 9000 action block;
                  import table on;
                 
                  import where dn_import_filter(${toString conf.latency}, ${toString conf.bandwidth}, ${toString conf.crypto});
                  export where dn_export_filter(${toString conf.latency}, ${toString conf.bandwidth}, ${toString conf.crypto});
                };
                
                neighbor ${conf.addr.v6}%'${conf.interface}' as ${builtins.toString conf.as};
                source address ${conf.srcAddr.v6};
              }
            '')
          cfg.peers))}

        protocol bgp ROUTE_COLLECTOR from dnpeers {
          neighbor fd42:4242:2601:ac12::1 as 4242422602;
          source address ${cfg.addr.v6};

          # enable multihop as the collector is not locally connected
          multihop;
          
          ipv4 {
            # export all available paths to the collector    
            add paths tx;

            # import/export filters
            import none;
            export filter {
              # export all valid routes
              if ( is_valid_network_v4() && source ~ [ RTS_STATIC, RTS_BGP ] )
              then {
                accept;
              }
              reject;
            };
          };

          ipv6 {
            # export all available paths to the collector    
            add paths tx;

            # import/export filters
            import none;
            export filter {
              # export all valid routes
              if ( is_valid_network_v6() && source ~ [ RTS_STATIC, RTS_BGP ] )
              then {
                accept;
              }
              reject;
            };
          };
        }
      '';
    };
  };
}
