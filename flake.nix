{
  description = "Minimal Oracle Cloud Always Free Headscale control plane";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, disko, ... }:
    let
      # Change these two values BEFORE deployment.
      domain = "my-headscale-mesh.duckdns.org";
      sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICIDqG/jSB08m63uiHllGLCljIQz4qK4UyKzUSzAjHga kupersmith3.6@gmail.com";
    in {
      nixosConfigurations.headscale-vps = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit domain sshPublicKey; };
        modules = [
          disko.nixosModules.disko
          ./disko.nix
          ./configuration.nix
        ];
      };
    };
}
