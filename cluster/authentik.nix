{kubenix, ...}: let
  version = "2026.2.2";
  env = [
    {
      name = "AUTHENTIK_SECRET_KEY";
      valueFrom.secretKeyRef = {
        name = "secret-key";
        key = "secret-key";
      };
    }
    {
      name = "AUTHENTIK_POSTGRESQL__PASSWORD";
      valueFrom.secretKeyRef = {
        name = "authentik-postgres";
        key = "password";
      };
    }
  ];
in {
  kubernetes.helm.releases.authentik = {
    chart = kubenix.lib.helm.fetch {
      inherit version;
      repo = "https://charts.goauthentik.io/";
      chart = "authentik";
      sha256 = "syF37Tymrvvfx5srWj0nRkTB5Us/qwvvVW6kHrHtRi0=";
    };

    values = {
      global.external_url = "https://auth.icytv.de";

      server = {
        inherit env;
        ingress.enabled = false;
      };

      postgresql = {
        enabled = true;
        auth = {
          existingSecret = "authentik-postgres";
          secretKeys.passwordKey = "password";
        };
      };
      redis.enabled = false;

      worker.env = env;
    };
  };

  kubernetes.resources = {
    ingresses.authentik.spec = {
      ingressClassName = "traefik";
      rules = [
        {
          host = "auth.icytv.de";
          http.paths = [
            {
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "authentik-server";
                port.number = 80;
              };
            }
          ];
        }
      ];
    };
  };
}
