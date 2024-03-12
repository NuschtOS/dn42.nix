{ pkgs ? import <nixpkgs> {} }:

let
  common = {
    imports = [ ../modules ];
    networking.dn42.enable = true;
    virtualisation.interfaces.enp1s0.vlan = 1;
    networking.useNetworkd = true;
    systemd.network.netdevs.dummy0.netdevConfig = {
      Kind = "dummy";
      Name = "dummy0";
    };
  };

in
pkgs.nixosTest rec {
  name = "two-peers";

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
          addr.v4 = (builtins.head nodes.bar.networking.interfaces.enp1s0.ipv4.addresses).address;
          addr.v6 = (builtins.head nodes.bar.networking.interfaces.enp1s0.ipv6.addresses).address;
          srcAddr.v4 = (builtins.head nodes.foo.networking.interfaces.enp1s0.ipv4.addresses).address;
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
          addr.v4 = (builtins.head nodes.foo.networking.interfaces.enp1s0.ipv4.addresses).address;
          addr.v6 = (builtins.head nodes.foo.networking.interfaces.enp1s0.ipv6.addresses).address;
          srcAddr.v4 = (builtins.head nodes.bar.networking.interfaces.enp1s0.ipv4.addresses).address;
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
    foo.wait_for_unit("bird2")
    bar.wait_for_unit("bird2")

    # Test basic reachability on the peering network
    foo.wait_until_succeeds("ping -c 1 10.0.0.2")
    bar.wait_until_succeeds("ping -c 1 10.0.0.1")

    # Assuming IPv4 peering is up, try ping on routed dummy0 addrs
    foo.wait_until_succeeds("ping -c 1 ${nodes.bar.networking.dn42.addr.v4}")
    bar.wait_until_succeeds("ping -c 1 ${nodes.foo.networking.dn42.addr.v4}")

    # icmpv6 unsupported by QEMU user networking
    # foo.wait_until_succeeds("ping -c 1 ${nodes.bar.networking.dn42.addr.v6}")
    # bar.wait_until_succeeds("ping -c 1 ${nodes.foo.networking.dn42.addr.v6}")
  '';
}
