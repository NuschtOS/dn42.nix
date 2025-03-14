{ self, pkgs }:

let
  bird = if pkgs.lib.versionAtLeast pkgs.lib.version "25.05" then "bird" else "bird2";

  common = { pkgs, ... }: {
    imports = [ self.nixosModules.default ];
    networking.dn42.enable = true;
    virtualisation.interfaces.enp1s0.vlan = 1;
    networking.useNetworkd = true;
    networking.domain = "text.nixos";
    systemd.network.netdevs.dummy0.netdevConfig = {
      Kind = "dummy";
      Name = "dummy0";
    };
    environment.systemPackages = [ pkgs.jq ];
    networking.dn42.roagen = {
      enable = true;
      outputDir = pkgs.runCommand "stub-roa" {} ''
        mkdir $out
        cat >$out/dn42-roa4.conf <<EOF
        route 172.20.0.0/24 max 24 as 64600;
        route 172.20.1.0/24 max 24 as 64601;
        EOF
        cat >$out/dn42-roa6.conf <<EOF
        route fec1::/64 max 64 as 64600;
        route fec1:0:0:1::/64 max 64 as 64601;
        EOF
      '';
    };
  };

in
pkgs.nixosTest rec {
  name = "two-peers";

  nodes = {
    foo = {
      imports = [ common ];
      networking.hostName = "foo";
      networking.dn42 = {
        as = 64600;
        geo = 41;
        country = 1276;
        addr.v4 = "172.20.0.1";
        nets.v4 = [ "172.20.0.0/24" ];
        addr.v6 = "fec1::1";
        nets.v6 = [ "fec1::/64" ];
        peers.bar = {
          as = 64601;
          latency = 1;
          bandwidth = 25;
          crypto = 31;
          transit = false;
          addr.v4 = (builtins.head nodes.bar.networking.interfaces.enp1s0.ipv4.addresses).address;
          addr.v6 = (builtins.head nodes.bar.networking.interfaces.enp1s0.ipv6.addresses).address;
          srcAddr.v4 = (builtins.head nodes.foo.networking.interfaces.enp1s0.ipv4.addresses).address;
          srcAddr.v6 = (builtins.head nodes.foo.networking.interfaces.enp1s0.ipv6.addresses).address;
          interface = "enp1s0";
        };
      };
      networking.interfaces.enp1s0 = {
        ipv4.addresses = [{
          address = "10.0.0.1";
          prefixLength = 24;
        }];
        ipv6.addresses = [{
          address = "fe80::1";
          prefixLength = 64;
        }];
      };
      networking.interfaces.dummy0 = {
        ipv4.addresses = [{
          address = nodes.foo.networking.dn42.addr.v4;
          prefixLength = 24;
        }];
        ipv6.addresses = [{
          address = nodes.foo.networking.dn42.addr.v6;
          prefixLength = 64;
        }];
      };
    };
    bar = {
      imports = [ common ];
      networking.hostName = "bar";
      networking.dn42 = {
        as = 64601;
        geo = 41;
        country = 1276;
        addr.v4 = "172.20.1.1";
        nets.v4 = [ "172.20.1.0/24" ];
        addr.v6 = "fec1:0:0:1::1";
        nets.v6 = [ "fec1:0:0:1::/64" ];
        peers.foo = {
          as = 64600;
          latency = 1;
          bandwidth = 25;
          crypto = 31;
          transit = false;
          addr.v4 = (builtins.head nodes.foo.networking.interfaces.enp1s0.ipv4.addresses).address;
          addr.v6 = (builtins.head nodes.foo.networking.interfaces.enp1s0.ipv6.addresses).address;
          srcAddr.v4 = (builtins.head nodes.bar.networking.interfaces.enp1s0.ipv4.addresses).address;
          srcAddr.v6 = (builtins.head nodes.bar.networking.interfaces.enp1s0.ipv6.addresses).address;
          interface = "enp1s0";
        };
      };
      networking.interfaces.enp1s0 = {
        ipv4.addresses = [{
          address = "10.0.0.2";
          prefixLength = 24;
        }];
        ipv6.addresses = [{
          address = "fe80::2";
          prefixLength = 64;
        }];
      };
      networking.interfaces.dummy0 = {
        ipv4.addresses = [{
          address = nodes.bar.networking.dn42.addr.v4;
          prefixLength = 24;
        }];
        ipv6.addresses = [{
          address = nodes.bar.networking.dn42.addr.v6;
          prefixLength = 64;
        }];
      };
    };
  };

  testScript = ''
    foo.succeed("ip -6 mon > /dev/console &")

    foo.wait_for_unit("${bird}")
    bar.wait_for_unit("${bird}")

    with subtest("Waiting for advertised IPv4 routes"):
      foo.wait_until_succeeds("ip --json r | jq -e 'map(select(.dst == \"${builtins.head nodes.bar.networking.dn42.nets.v4}\")) | any'")
      bar.wait_until_succeeds("ip --json r | jq -e 'map(select(.dst == \"${builtins.head nodes.foo.networking.dn42.nets.v4}\")) | any'")

    # Assuming IPv4 peering is up, try ping on routed dummy0 addrs
    foo.wait_until_succeeds("ping -c 1 ${nodes.bar.networking.dn42.addr.v4}")
    bar.wait_until_succeeds("ping -c 1 ${nodes.foo.networking.dn42.addr.v4}")

    # with subtest("Waiting for advertised IPv6 routes"):
    #   foo.wait_until_succeeds("ip --json -6 r | jq -e 'map(select(.dst == \"${builtins.head nodes.bar.networking.dn42.nets.v6}\")) | any'")
    #   bar.wait_until_succeeds("ip --json -6 r | jq -e 'map(select(.dst == \"${builtins.head nodes.foo.networking.dn42.nets.v6}\")) | any'")

    # icmpv6 unsupported by QEMU user networking
    # foo.wait_until_succeeds("ping -c 1 ${nodes.bar.networking.dn42.addr.v6}")
    # bar.wait_until_succeeds("ping -c 1 ${nodes.foo.networking.dn42.addr.v6}")
  '';
}
