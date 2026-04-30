{
  kubenix,
  lib,
  ...
}: let
  version = "0.41.0";
in {
  kubernetes.helm.releases.headlamp = {
    chart = kubenix.lib.helm.fetch {
      inherit version;
      repo = "https://kubernetes-sigs.github.io/headlamp/";
      chart = "headlamp";
      sha256 = "wkpCwEwUtjp9v8Wri6/kX6A+ezhV+ryARv6caCzenVg=";
    };

    values = {
      ingress = {
        enabled = true;
        ingressClassName = "traefik";
        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "web";
        };
        hosts = [
          {
            host = "cluster.icytv.de";
            paths = [
              {
                path = "/";
                type = "Prefix";
              }
            ];
          }
        ];
      };

      config = {
        watchPlugins = true;
        oidc = {
          secret.create = false;
          externalSecret = {
            enbled = true;
            name = "oidc-secret";
          };
        };
      };

      pluginsManager.enabled = true;

      persistentVolumeClaim.enabled = false;
    };
  };
}
