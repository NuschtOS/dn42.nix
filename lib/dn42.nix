{
  lib,
  ...
}:
let
  template = ownAs: ''
    local as ${toString ownAs};

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
in
{
  mkPeerV4 =
    {
      name,
      ownAs,
      remoteAs,
      ownIp,
      remoteIp,

      # bgp communities
      latency,
      bandwidth,
      crypto,
      transit,
    }:
    ''
      protocol bgp ${name}_4 {
        ${template ownAs}

        neighbor ${remoteIp} as ${builtins.toString remoteAs};
        source address ${ownIp};

        ipv4 {
          import limit 9000 action block;
          import table on;

          import where dn_import_filter4(${toString latency}, ${toString bandwidth}, ${toString crypto});
          export where dn_export_filter4(${toString latency}, ${toString bandwidth}, ${toString crypto}, ${lib.boolToString transit});
        };
      }
    '';
  mkPeerV6 =
    {
      name,
      ownAs,
      remoteAs,
      ownIp,
      remoteIp,
      ownInterface,

      # bgp communities
      latency,
      bandwidth,
      crypto,
      transit,

      # whether ipv4 session should be configured for the ipv6 neighbor
      extendedNextHop,
    }:
    ''
      protocol bgp ${name}_6 {
        ${template ownAs}

        ${lib.optionalString extendedNextHop ''
          enable extended messages on;

          ipv4 {
            import limit 9000 action block;
            import table on;

            extended next hop on;
            import where dn_import_filter4(${toString latency}, ${toString bandwidth}, ${toString crypto});
            export where dn_export_filter4(${toString latency}, ${toString bandwidth}, ${toString crypto}, ${lib.boolToString transit});
          };
        ''}

        ipv6 {
          import limit 9000 action block;
          import table on;

          import where dn_import_filter6(${toString latency}, ${toString bandwidth}, ${toString crypto});
          export where dn_export_filter6(${toString latency}, ${toString bandwidth}, ${toString crypto}, ${lib.boolToString transit});
        };

        neighbor ${remoteIp}%'${ownInterface}' as ${toString remoteAs};
        source address ${ownIp};
      }
    '';
}
