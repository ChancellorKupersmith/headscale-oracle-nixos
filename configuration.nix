{
  lib,
  domain,
  sshPublicKey,
  pkgs,
  ...
}:
let
  # Paste the PUBLIC signing key printed on mini by:
  # sudo sh -c 'nix key convert-secret-to-public < /var/cache/nix/cachemini-private.key'
  # Keep the corresponding private key on mini only.
  cacheminiPublicKey = "cachemini-1:ULsw0ejlyGDJTSIAHtJFbuaISfsTunlb9HnQy4FpYkI=";

  # Assumes this flake lives in a private GitHub repo at this URL.
  # Change the repo name if your actual remote differs.
  deploymentFlake = "git+ssh://git@github.com/ChancellorKupersmith/headscale-oracle-nixos.git?ref=master#headscale-vps";
in
{
  system.stateVersion = "26.05";
  networking.hostName = "headscale-vps";

  # OCI's Ubuntu cloud image usually uses DHCP. Record `ip route` and
  # `ip -4 addr` BEFORE reinstall; use static networking if DHCP is absent.
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.allowedTCPPorts = [
    22
    80
    443
  ];

  # The OCI ARM VM should boot using UEFI; verify /sys/firmware/efi before install.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "nvme"
    "xhci_pci"
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

  # Trust GitHub's SSH host key for unattended read-only flake fetches.
  services.openssh.knownHosts.github = {
    hostNames = [ "github.com" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };

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
        nameservers.global = [ ];
      };
      database.type = "sqlite";
      derp.server.enabled = false;
      trusted_proxies = [
        "127.0.0.1/32"
        "::1/128"
      ];
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

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # A lower priority number wins when both caches have the same path.
    extra-substituters = [ "https://cache-pull.showready.xyz?priority=30" ];
    extra-trusted-public-keys = lib.optional (cacheminiPublicKey != null) cacheminiPublicKey;
  };

  # Updates at 05:00 Pacific, after mini's existing 03:00 builder job.
  # This pulls the committed lockfile: Oracle never advances inputs itself.
  system.autoUpgrade = {
    enable = true;
    flake = deploymentFlake;
    upgrade = false;
    operation = "switch";
    allowReboot = false;
    dates = "*-*-* 05:00:00 America/Los_Angeles";
    randomizedDelaySec = "0";
    persistent = false;
    flags = [ "--print-build-logs" ];
  };

  # Root's private key is created manually outside /nix/store. GitHub gets
  # only the matching read-only *public* deploy key, not this private key.
  systemd.services.nixos-upgrade.environment.GIT_SSH_COMMAND =
    "ssh -F /dev/null -i /root/.ssh/headscale-deploy -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes";
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  environment.systemPackages = with pkgs; [
    git
    openssh
  ];
}
