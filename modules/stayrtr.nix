{ config, lib, pkgs, ... }:

let
  cfg = config.networking.dn42.stayrtr;
in
{
  options.networking.dn42.stayrtr = with lib; {
    enable = mkEnableOption "dn42-stayrtr";

    cache = mkOption {
      type = types.str;
      default = "https://dn42.burble.com/roa/dn42_roa_46.json";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.dn42-stayrtr = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.stayrtr}/bin/stayrtr -cache '${cfg.cache}' -checktime=false -bind :8082";
        DynamicUser = true;
        User = "dn42-stayrtr";
      };
    };
  };
}
