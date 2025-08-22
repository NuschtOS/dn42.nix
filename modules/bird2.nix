{ config, lib, ... }:

let
  cfg = config.networking.dn42;
  useVrf = cfg.vrf.name != null && cfg.vrf.table != null;
  bird = if lib.versionAtLeast lib.version "25.05" then "bird" else "bird2";
in
{
  config = lib.mkIf cfg.enable {
    assertions =
      builtins.attrValues (
        builtins.mapAttrs (peer: conf: {
          assertion = !conf.extendedNextHop -> conf.addr.v4 != null && conf.srcAddr.v4 != null;
          message = "dn42.nix peer ${peer}: IPv4 addresses are required, consider using extended next hop.";
        }) cfg.peers
      )
      ++
      builtins.attrValues (
        builtins.mapAttrs (peer: conf: {
          assertion = conf.extendedNextHop -> conf.addr.v4 == null && conf.srcAddr.v4 == null;
          message = "dn42.nix peer ${peer}: IPv4 addresses are disallowed, consider not using extended next hop.";
        }) cfg.peers
      );

    services.${bird} = {
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

        ${lib.optionalString useVrf ''
        ipv4 table ${cfg.vrf.name}_4;
        ipv6 table ${cfg.vrf.name}_6;
        ''}
        roa4 table dnroa_4;
        roa6 table dnroa_6;

        include "${../resources/community_filter.conf}";
        include "${../resources/filters.conf}";
      '';

      inherit (cfg) routerId;

      templates.bgp.dn42_peer = ''
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
      '';

      protocols = {

        rpki.roa_dn42 = lib.mkIf config.networking.dn42.stayrtr.enable ''
          roa4 { table dnroa_4; };
          roa6 { table dnroa_6; };
          remote 127.0.0.1;
          port 8082;
          refresh 600;
          retry 300;
          expire 7200;
        '';

        static = {
          static_roa_4 = lib.mkIf config.networking.dn42.roagen.enable ''
            roa4 { table dnroa_4; };
            include "${config.networking.dn42.roagen.outputDir}/dn42-roa4.conf";
          '';
          static_roa_6 = lib.mkIf config.networking.dn42.roagen.enable ''
            roa6 { table dnroa_6; };
            include "${config.networking.dn42.roagen.outputDir}/dn42-roa6.conf";
          '';
          static_4 = ''
            ${lib.optionalString useVrf "vrf \"${cfg.vrf.name}\";"}
            ipv4 {
              ${lib.optionalString useVrf "table ${cfg.vrf.name}_4;"}
            };

            ${lib.concatMapStrings (net: ''
              route ${net} unreachable;
            '') cfg.nets.v4}
          '';
          static_6 = ''
            ${lib.optionalString useVrf "vrf \"${cfg.vrf.name}\";"}
            ipv6 {
              ${lib.optionalString useVrf "table ${cfg.vrf.name}_6;"}
            };

            ${lib.concatMapStrings (net: ''
              route ${net} unreachable;
            '') cfg.nets.v6}
          '';
        };

        device."" = ''
          scan time 10;
        '';

        kernel = {
          kernel_4 = ''
            ${lib.optionalString useVrf ''
            vrf "${cfg.vrf.name}";
            kernel table ${toString cfg.vrf.table};
            ''}
            scan time 20;

            ipv4 {
              ${lib.optionalString useVrf "table ${cfg.vrf.name}_4;"}

              import none;
              export filter {
                if source = RTS_STATIC then reject;
                krt_prefsrc = ${cfg.addr.v4};
                accept;
              };
            };
          '';

          kernel_6 = ''
            ${lib.optionalString useVrf ''
            vrf "${cfg.vrf.name}";
            kernel table ${toString cfg.vrf.table};
            ''}
            scan time 20;

            ipv6 {
              ${lib.optionalString useVrf "table ${cfg.vrf.name}_6;"}

              import none;
              export filter {
                if source = RTS_STATIC then reject;
                krt_prefsrc = ${cfg.addr.v6};
                accept;
              };
            };
          '';
        };

        bgp = lib.mkMerge
          ((lib.mapAttrsToList
            (name: conf:
              {
                "${name}_4 from dn42_peer" = lib.mkIf (!conf.extendedNextHop) ''
                  ${lib.optionalString useVrf "vrf \"${cfg.vrf.name}\";"}
                  neighbor ${conf.addr.v4} as ${builtins.toString conf.as};
                  source address ${conf.srcAddr.v4};

                  ipv4 {
                    ${lib.optionalString useVrf "table ${cfg.vrf.name}_4;"}
                    import limit 9000 action block;
                    import table on;
                    import where dn_import_filter4(${toString conf.latency}, ${toString conf.bandwidth}, ${toString conf.crypto});
                    export where dn_export_filter4(${toString conf.latency}, ${toString conf.bandwidth}, ${toString conf.crypto}, ${lib.boolToString conf.transit});
                  };
                '';

                "${name}_6 from dn42_peer" = ''
                  ${lib.optionalString useVrf "vrf \"${cfg.vrf.name}\";"}
                  interface "${conf.interface}";
                  neighbor ${conf.addr.v6} as ${builtins.toString conf.as};
                  source address ${conf.srcAddr.v6};

                  ${lib.optionalString conf.extendedNextHop ''
                    enable extended messages on;

                    ipv4 {
                      ${lib.optionalString useVrf "table ${cfg.vrf.name}_4;"}
                      import limit 9000 action block;
                      import table on;

                      extended next hop on;
                      import where dn_import_filter4(${toString conf.latency}, ${toString conf.bandwidth}, ${toString conf.crypto});
                      export where dn_export_filter4(${toString conf.latency}, ${toString conf.bandwidth}, ${toString conf.crypto}, ${lib.boolToString conf.transit});
                    };
                  ''}

                  ipv6 {
                    ${lib.optionalString useVrf "table ${cfg.vrf.name}_6;"}
                    import limit 9000 action block;
                    import table on;

                    import where dn_import_filter6(${toString conf.latency}, ${toString conf.bandwidth}, ${toString conf.crypto});
                    export where dn_export_filter6(${toString conf.latency}, ${toString conf.bandwidth}, ${toString conf.crypto}, ${lib.boolToString conf.transit});
                  };
                '';
              })
            cfg.peers)
          ++ [{
            "collector_6 from dn42_peer" = ''
              ${lib.optionalString useVrf "vrf \"${cfg.vrf.name}\";"}
              neighbor fd42:4242:2601:ac12::1 as 4242422602;
              source address ${cfg.addr.v6};

              # enable multihop as the collector is not locally connected
              multihop;

              ipv4 {
                ${lib.optionalString useVrf "table ${cfg.vrf.name}_4;"}
                # export all available paths to the collector
                add paths tx;

                # import/export filters
                import none;
                export where dn_export_collector4();
              };

              ipv6 {
                ${lib.optionalString useVrf "table ${cfg.vrf.name}_6;"}
                # export all available paths to the collector
                add paths tx;

                # import/export filters
                import none;
                export where dn_export_collector6();
              };
            '';
          }]);
      };
    };
  };
}
