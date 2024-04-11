{ pkgs, ... }:

{
  systemd.services.dn42-stayrtr = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.stayrtr}/bin/stayrtr -cache https://dn42.burble.com/roa/dn42_roa_46.json -checktime=false -bind :8082";
      DynamicUser = true;
      User = "dn42-stayrtr";
    };
  };
}
