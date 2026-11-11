{ lib, domain, sshPublicKey, ... }:
{
  system.stateVersion = "26.05";
  networking.hostName = "headscale-vps";

  # OCI's Ubuntu cloud image usually uses DHCP. Record `ip route` and
  # `ip -4 addr` BEFORE reinstall; use static networking if DHCP is absent.
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];

  # The OCI ARM VM should boot using UEFI; verify /sys/firmware/efi before install.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = [
    "virtio_pci" "virtio_scsi" "virtio_blk" "nvme" "xhci_pci"
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  users.users.root.openssh.authorizedKeys.keys = [ sshPublicKey ];

  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = 8080;
    settings = {
      server_url = "https://${domain}";
      dns = {
        magic_dns = true;
        # Local-only MagicDNS names (different from public control URL).
        base_domain = "mesh.internal";
        override_local_dns = false;
      };
      database.type = "sqlite";
      derp.server.enabled = false;
      trusted_proxies = [ "127.0.0.1/32" "::1/128" ];
    };
  };

  services.caddy = {
    enable = true;
    virtualHosts."http://${domain}".extraConfig = ''
      handle /generate_204 {
        respond 204
      }
      handle {
        redir https://${domain}{uri} permanent
      }
    '';
    virtualHosts."${domain}".extraConfig = ''
      reverse_proxy 127.0.0.1:8080 {
        header_up True-Client-IP {remote_host}
        header_up X-Real-IP {remote_host}
      }
    '';
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
}
