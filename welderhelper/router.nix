{ config, lib, pkgs, ... }:

let cfg = {
      nic = "eno1";
      uplinkVlanId = 60;
      localVlanId = 90;
    };

    vlanUplink = "wan${toString cfg.uplinkVlanId}";
    vlanLocal = "lan${toString cfg.localVlanId}";

in {
  networking.networkmanager.enable = lib.mkForce false;
  networking.nameservers = [ "8.8.8.8" ];
  networking.enableIPv6 = lib.mkForce false;  
  
  # Enable Kernel IP Forwarding.
  #
  # For more details, refer to
  # https://unix.stackexchange.com/questions/14056/what-is-kernel-ip-forwarding
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv4.conf.default.forwarding" = true;
    # TODO(breakds): Enable this for ipv6 
    # "net.ipv6.conf.all.forwarding" = true;
    # "net.ipv6.conf.default.forwarding" = true;
  };


  # Create 2 separate VLAN devices for the NIC (e.g. eno1). One of the
  # VLAN device will be used for the uplink, and the other one will be
  # used for the internal network.

  networking.vlans = {
    # uplink
    "${vlanUplink}" = {
      id = cfg.uplinkVlanId;
      interface = cfg.nic;
    };

    # internal
    "${vlanLocal}" = {
      id = cfg.localVlanId;
      interface = cfg.nic;
    };
  };

  # Enable DHCP
  services.dhcpd4 = {
    enable = true;
    interfaces = [ vlanLocal ];
    machines = [
      {
        ethernetAddress = "B4:2E:99:31:7D:95";
        hostName = "gilgamesh";
        ipAddress = "10.77.1.117";
      }
    ];
    extraConfig = ''
      option domain-name-servers 1.1.1.1, 8.8.8.8, 8.8.4.4;
      option subnet-mask 255.255.255.0;

      default-lease-time 25920000;
      max-lease-time 25920000;
      
      subnet 10.77.1.0 netmask 255.255.255.0 {
        interface ${vlanLocal};
        range 10.77.1.20 10.77.1.240;
        option routers 10.77.1.1;
        option broadcast-address 10.77.1.255;
      }
    '';
  };

  # Firewall
  networking.firewall = {
    enable = true;
    allowPing = true;
    logRefusedConnections = false;
    # If rejectPackets = true, refused packets are rejected rather than dropped (ignored). This
    # means that an ICMP "port unreachable" error message is sent back to the client (or a TCP RST
    # packet in case of an existing connection). Rejecting packets makes port scanning somewhat
    # easier.
    rejectPackets = false;
    # Traffic coming in from these interfaces will be accepted unconditionally. Traffic from the
    # loopback (lo) interface will always be accepted.
    trustedInterfaces = [ vlanLocal ];
    # Do not perform reverse path filter test on a packet.
    checkReversePath = false;
  };

  # NAT
  networking.nat = {
    enable = true;
    externalInterface = vlanUplink;
    internalInterfaces = [ vlanLocal ];
    internalIPs = [ "10.77.1.0/24" ];
    forwardPorts = [
      { sourcePort = 22; destination = "10.77.1.117:22"; loopbackIPs = [ "23.119.127.221" ]; }
      { sourcePort = 80; destination = "10.77.1.117:80"; loopbackIPs = [ "23.119.127.221" ]; }
      { sourcePort = 443; destination = "10.77.1.117:443"; loopbackIPs = [ "23.119.127.221" ]; }
    ];
  };

  # Topology for the managed switch:
  #
  #
  #
  #  +-----+-----+-----+
  #  |  A  |  B  |  C  | <- managed switch
  #  |     |     |     |
  #  +--|--+--|--+--|--+  
  #     |     |     +------------------ Wifi AP/Devices
  #     |     |
  #     |     +------------ Modem
  #   router
  #
  # If the vlan ID for wan is 60, and the vlan ID for lan is 90, we
  # need to configure
  #
  # 1. A as a Trunk Port that allows 60 and 90
  # 2. B as an Access (Untagged) Port with Vlan ID (and PVID) = 60
  # 3. C as an Access (Untagged) Port with Vlan ID (and PVID) = 90
  networking.interfaces."${cfg.nic}".useDHCP = false;
  # Let the modem "DHCP me" for the uplink VLAN.
  networking.interfaces."${vlanUplink}".useDHCP = true;
  networking.interfaces."${vlanLocal}" = {
    # This is going to be the router's IP to internal devices connects
    # to it.
    ipv4.addresses = [ {
      address = "10.77.1.1";
      prefixLength = 24;  # Subnet Mask = 255.255.255.0
    } ];
    useDHCP = false;
  };

  # iperf3 Server for speed/bandwidth testing
  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  # Other helpful tools
  environment.systemPackages = with pkgs; [
    tcpdump ethtool
  ];
}
