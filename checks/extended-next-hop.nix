{ pkgs ? import <nixpkgs> {} }:

let
  common = { pkgs, ... }: {
    imports = [ ../modules ];
    networking.dn42.enable = true;
    virtualisation.interfaces.enp1s0.vlan = 1;
    networking.useNetworkd = true;
    systemd.network.netdevs.dummy0.netdevConfig = {
      Kind = "dummy";
      Name = "dummy0";
    };
    environment.systemPackages = [ pkgs.jq ];
  };

in
pkgs.nixosTest rec {
  name = "extended-next-hop";

  nodes = {
    foo = {
      imports = [ common ];
      networking.dn42 = {
        as = 64600;
        addr.v4 = "172.20.0.1";
        nets.v4 = [ "172.20.0.0/24" ];
        addr.v6 = "fec0::1";
        nets.v6 = [ "fec0::/64" ];
        peers.bar = {
          as = 64601;
          extendedNextHop = true;
          addr.v6 = (builtins.head nodes.bar.networking.interfaces.enp1s0.ipv6.addresses).address;
          srcAddr.v6 = (builtins.head nodes.foo.networking.interfaces.enp1s0.ipv6.addresses).address;
          interface = "enp1s0";
        };
      };
      networking.interfaces.enp1s0 = {
        ipv4.addresses = [ {
          address = "10.0.0.1";
          prefixLength = 24;
        } ];
        ipv6.addresses = [ {
          address = "fe80::1";
          prefixLength = 64;
        } ];
      };
      networking.interfaces.dummy0 = {
        ipv4.addresses = [ {
          address = nodes.foo.networking.dn42.addr.v4;
          prefixLength = 24;
        } ];
        ipv6.addresses = [ {
          address = nodes.foo.networking.dn42.addr.v6;
          prefixLength = 64;
        } ];
      };
    };
    bar = {
      imports = [ common ];
      networking.dn42 = {
        as = 64601;
        addr.v4 = "172.20.1.1";
        nets.v4 = [ "172.20.1.0/24" ];
        addr.v6 = "fec0:0:0:1::1";
        nets.v6 = [ "fec0:0:0:1::/64" ];
        peers.foo = {
          as = 64600;
          extendedNextHop = true;
          addr.v6 = (builtins.head nodes.foo.networking.interfaces.enp1s0.ipv6.addresses).address;
          srcAddr.v6 = (builtins.head nodes.bar.networking.interfaces.enp1s0.ipv6.addresses).address;
          interface = "enp1s0";
        };
      };
      networking.interfaces.enp1s0 = {
        ipv4.addresses = [ {
          address = "10.0.0.2";
          prefixLength = 24;
        } ];
        ipv6.addresses = [ {
          address = "fe80::2";
          prefixLength = 64;
        } ];
      };
      networking.interfaces.dummy0 = {
        ipv4.addresses = [ {
          address = nodes.bar.networking.dn42.addr.v4;
          prefixLength = 24;
        } ];
        ipv6.addresses = [ {
          address = nodes.bar.networking.dn42.addr.v6;
          prefixLength = 64;
        } ];
      };
    };
  };

  testScript = ''
    foo.succeed("ip -6 mon > /dev/console &")

    foo.wait_for_unit("bird2")
    bar.wait_for_unit("bird2")

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
