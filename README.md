# Oracle Always Free -> NixOS 26.05 -> Headscale + Caddy

This is a starting template, not a tested deployment on your particular OCI VM.
It intentionally omits client enrolment and DERP hosting until the control plane is healthy.

## 1. Provision the VM via the Oracle Cloud console

- Sign up at https://signup.oraclecloud.com . Pick your home region deliberately: Always Free compute runs only there.
- Create a VCN with Internet Connectivity and a **public** subnet.
- Compute > Instances > Create instance: `headscale-vps`.
- Image: Ubuntu LTS **aarch64** (Always Free Eligible).
- Shape: VM.Standard.A1.Flex with 1 OCPU, 6 GB RAM (within the Oracle Always Free envelope reported in Nov 2026).
- Boot volume: default minimum (typically ~47 GB), not a paid high-performance option.
- Public IPv4: yes. Upload your local laptop's **public** SSH key.
- Security list ingress: TCP 22 (ideally only from your current public /32), 80 and 443 (from 0.0.0.0/0).
- Do not upgrade to Pay As You Go solely to resolve a capacity failure.

## 2. Verify original VM

On your laptop, replace the example with the actual VM IPv4:

```bash
export VPS_IP=203.0.113.10
ssh ubuntu@"$VPS_IP" 'uname -m; lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS; test -d /sys/firmware/efi && echo UEFI=yes || echo UEFI=no; ip -4 addr; ip -4 route; sudo -n true && echo SUDO=ok'
```

Check architecture is `aarch64`, boot is UEFI, sudo works without a password, the boot disk path matches **disko.nix** (default `/dev/sda`), and network addressing really uses DHCP. If not, modify the template instead of proceeding blindly.

## 3. Configure public DNS

Use your own domain's A record, or DuckDNS (https://www.duckdns.org/) for a free subdomain, pointing to the public IPv4. Do **not** proxy traffic through Cloudflare (Headscale's control protocol is not supported there).

Edit `flake.nix`:

- `domain = "REPLACE-ME.duckdns.org";` -> real hostname (no scheme).
- `sshPublicKey = "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY";` -> `cat ~/.ssh/id_ed25519.pub` from your laptop.

If `/dev/sda` is not the OS disk, edit `disko.nix`. Optionally restrict SSH at OCI's VCN security list to your public IP.

Check DNS with `dig +short yourname.duckdns.org`.

## 4. Install (DESTROYS ORIGINAL UBUNTU VM)

From the folder containing this flake, on your x86_64 NixOS laptop:

```bash
nix --extra-experimental-features 'nix-command flakes' flake lock
nix --extra-experimental-features 'nix-command flakes' eval --raw .#nixosConfigurations.headscale-vps.config.services.headscale.settings.server_url
nix --extra-experimental-features 'nix-command flakes' run github:nix-community/nixos-anywhere -- \
  --flake .#headscale-vps --build-on remote --target-host "ubuntu@$VPS_IP"
```

If your SSH identity is nonstandard, append `-i ~/.ssh/YOUR_PRIVATE_KEY` (NOT your `.pub` key). `nixos-anywhere` logs in via Ubuntu's passwordless sudo, then **erases and repartitions** the selected disk. Its kexec step and bootloader setup are not guaranteed to work on every OCI image; the OCI serial console is the recovery mechanism.

After reboot, SSH login is `root@${VPS_IP}` with your previously configured authorized public key. Your SSH host key changes during OS replacement; compare the new host fingerprint with the serial console before trusting it.

## 5. Check Headscale

```bash
ssh root@"$VPS_IP" 'systemctl is-active sshd headscale caddy; headscale users create homelab; headscale users list'
curl -fsS https://YOUR_HOSTNAME/health
```

The health endpoint must respond successfully over publicly trusted HTTPS. Client registration is a separate next step.

## 6. Maintenance

- Save `flake.nix`, `disko.nix`, `configuration.nix`, and `flake.lock` in Git.
- Back up `/var/lib/headscale` (SQLite + machine identity). Handle SQLite safely via service stop or `.backup` rather than blind live copies.
- Don't expose TCP 8080, 9090, or Headscale's gRPC port to the internet.
- Expect OCI free instances to be subject to idle reclamation and capacity limitations. Use a backup/restore plan.
- To upgrade, evaluate and deploy a new flake revision using a remote NixOS rebuild strategy (e.g., `nixos-rebuild switch --flake .#headscale-vps --target-host root@IP --build-host root@IP`).

Official references:
- https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm
- https://nix-community.github.io/nixos-anywhere/quickstart.html
- https://wiki.nixos.org/wiki/Install_NixOS_on_Oracle_Cloud
- https://headscale.net/stable/ref/integration/reverse-proxy/
- https://headscale.net/stable/usage/getting-started/
