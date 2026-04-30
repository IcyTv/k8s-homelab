{
  kubenix,
  lib,
  ...
}: {
  imports = [
    kubenix.modules.k8s
    kubenix.modules.helm
    kubenix.modules.submodules
    ../submodules/namespaced.nix
  ];

  kubenix.project = "icytv-homelab";

  submodules.imports = [
    ../submodules/namespaced.nix
  ];

  submodules.instances =
    builtins.mapAttrs (_name: value: {
      submodule = "namespaced";
      args = import value {inherit kubenix lib;};
    }) {
      traefik = ./traefik.nix;
      tailscale = ./tailscale.nix;
      homeassistant = ./homeassistant.nix;
      headlamp = ./headlamp.nix;
      cloudflared = ./cloudflared.nix;
      authentik = ./authentik.nix;
      audiobookshelf = ./audiobookshelf.nix;
    };
}
