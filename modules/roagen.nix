{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.networking.dn42.roagen;
in
{
  options.networking.dn42.roagen = with lib; {
    enable = mkEnableOption "dn42-roagen";

    outputDir = mkOption {
      type = types.path;
      default = "/var/lib/dn42-roa";
      description = ''
        This directory will be created with files:
        - dn42-roa4.conf
        - dn42-roa6.conf
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.timers.dn42-roagen = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = "hourly";
    };

    systemd.services.dn42-roagen = {
      after = [ "systemd-tmpfiles-setup.service" ];
      before = [ "bird2.service" ];
      wantedBy = [ "bird2.service" ];
      script = ''
        set -e

        cd /tmp
        if [ ! -e registry ]; then
          ${lib.getExe pkgs.gitMinimal} clone --depth=1 https://git.dn42.dev/dn42/registry.git
          cd registry
        else
          cd registry
          ${lib.getExe pkgs.gitMinimal} pull --depth=1
        fi

        mkdir -p '${cfg.outputDir}'
        ${lib.getExe pkgs.dn42-roagen} /tmp/registry '${cfg.outputDir}'

        /run/current-system/sw/bin/systemctl reload bird2
      '';
      serviceConfig = {
        PrivateTmp = true;
        Type = "oneshot";
        User = "bird2";
        Group = "bird2";
      };
    };

    systemd.tmpfiles.rules = [ "d ${cfg.outputDir} 755 bird2 bird2 -" ];
  };
}
