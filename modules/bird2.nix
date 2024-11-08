{ config, lib, libDn42, ... }:

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

        define REGION_GEO = ${toString cfg.geo};
        define REGION_COUNTRY = ${toString cfg.country};

        define ASN_BLACKLIST = [];

        function is_self_net4() -> bool {
          return net ~ [${builtins.concatStringsSep ", " cfg.nets.v4}];
        }

        function is_self_net6() -> bool {
          return net ~ [${builtins.concatStringsSep ", " cfg.nets.v6}];
        }

        roa4 table dnroa4;
        roa6 table dnroa6;

        ${lib.optionalString config.networking.dn42.stayrtr.enable ''
          protocol rpki roa_dn42 {
            roa4 { table dnroa4; };
            roa6 { table dnroa6; };
            remote 127.0.0.1;
            port 8082;
            refresh 600;
            retry 300;
            expire 7200;
          }
        ''}
        ${lib.optionalString config.networking.dn42.roagen.enable ''
          protocol static {
            roa4 { table dnroa4; };
            include "${config.networking.dn42.roagen.outputDir}/dn42-roa4.conf";
          }
          protocol static {
            roa6 { table dnroa6; };
            include "${config.networking.dn42.roagen.outputDir}/dn42-roa6.conf";
          }
        ''}

        include "${../resources/community_filter.conf}";
        include "${../resources/filters.conf}";
      
        router id ${cfg.routerId};
        hostname "${config.networking.hostName}.${config.networking.domain}";

        protocol device {
          scan time 10;
        }
   
        protocol kernel kernel_4 {
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

        protocol kernel kernel_6 {
          scan time 20;

          ipv6 {
            import none;
            export filter {
              if source = RTS_STATIC then reject;
              krt_prefsrc = ${cfg.addr.v6};
              accept;
            };
          };
        }

        protocol static static_4 {
          ${lib.concatMapStrings (net: ''
            route ${net} unreachable;
          '') cfg.nets.v4}

          ipv4 {
            import all;
            export none;
          };
        }

        protocol static static_6 {
          ${lib.concatMapStrings (net: ''
            route ${net} unreachable;
          '') cfg.nets.v6}
          
          ipv6 {
            import all;
            export none;
          };
        }

        ${builtins.concatStringsSep "\n" (builtins.attrValues
          (builtins.mapAttrs
            (name: conf: ''
              ${lib.optionalString (!conf.extendedNextHop) (
              libDn42.mkPeerV4 {
                inherit name;
                ownAs = cfg.as;
                remoteAs = conf.as;
                ownIp = conf.srcAddr.v4;
                remoteIp = conf.addr.v4;
                
                # bgp communities
                latency = conf.latency;
                bandwidth = conf.bandwidth;
                crypto = conf.crypto;
                transit = conf.transit;
              })};

              ${libDn42.mkPeerV6 {
                inherit name;
                ownAs = cfg.as;
                remoteAs = conf.as;
                ownIp = conf.srcAddr.v6;
                remoteIp = conf.addr.v6;
                ownInterface = conf.interface;
                
                # bgp communities
                latency = conf.latency;
                bandwidth = conf.bandwidth;
                crypto = conf.crypto;
                transit = conf.transit;

                extendedNextHop = true;
              }};
            '')
          cfg.peers))}

        protocol bgp collector_6 from dnpeers {
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

          neighbor fd42:4242:2601:ac12::1 as 4242422602;
          source address ${cfg.addr.v6};

          # enable multihop as the collector is not locally connected
          multihop;

          ipv4 {
            # export all available paths to the collector    
            add paths tx;

            # import/export filters
            import none;
            export where dn_export_collector4();
          };

          ipv6 {
            # export all available paths to the collector    
            add paths tx;

            # import/export filters
            import none;
            export where dn_export_collector6();
          };
        }
      '';
    };
  };
}
