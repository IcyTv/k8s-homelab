{...}: let
  name = "cloudflared";
  version = "2026.3.0";

  configContent =
    #yaml
    ''
      tunnel: 589ee03f-e779-44e2-8a72-d7b2b205d895
      credentials-file: /etc/cloudflared/credentials.json
      metrics: 0.0.0.0:2000
      no-autoupdate: true
      originRequest:
        noTLSVerify: true
      ingress:
        - hostname: icytv.de
          service: http://traefik.traefik.svc.cluster.local:80
        - hostname: "*.icytv.de"
          service: http://traefik.traefik.svc.cluster.local:80
        - service: http_status:444
    '';

  configHash = builtins.hashString "sha256" configContent;
in {
  kubernetes.resources = {
    deployments.cloudflared.spec = {
      replicas = 2;
      selector.matchLabels.app = name;
      template = {
        metadata = {
          annotations = {
            "checksun/config" = configHash;
          };
          labels.app = name;
        };

        spec = {
          containers.cloudflared = {
            image = "cloudflared/cloudflared:${version}";
            imagePullPolicy = "IfNotPresent";
            args = ["tunnel" "--config" "/etc/cloudflared/config.yaml" "--no-autoupdate" "run"];
            env = [
              {
                name = "TUNNEL_TRANSPORT_PROTOCOL";
                value = "http2";
              }
              {
                name = "TUNNEL_EDGE_IP_VERSION";
                value = "4";
              }
            ];

            ports = [
              {
                name = "metrics";
                containerPort = 2000;
                protocol = "TCP";
              }
            ];

            livenessProbe = {
              tcpSocket.port = "metrics";
              initialDelaySeconds = 30;
              periodSeconds = 30;
              timeoutSeconds = 5;
              failureThreshold = 3;
            };

            readinessProbe = {
              httpGet = {
                path = "/ready";
                port = "metrics";
              };
              initialDelaySeconds = 20;
              periodSeconds = 15;
              timeoutSeconds = 10;
              failureThreshold = 5;
              successThreshold = 1;
            };

            resources = {
              requests = {
                cpu = "50m";
                memory = "64Mi";
              };
              limits = {
                cpu = "200m";
                memory = "128Mi";
              };
            };

            volumeMounts = {
              "/etc/cloudflared/config.yaml" = {
                name = "config";
                subPath = "config.yaml";
              };
              "/etc/cloudflared/credentials.json" = {
                name = "credentials";
                subPath = "credentials.json";
              };
            };
          };

          volumes = {
            config.configMap.name = "cloudflared-config";
            credentials.secret.secretName = "cloudflared-credentials";
          };
        };
      };
    };

    configMaps.cloudflared-config = {
      metadata.labels = {
        "app.kubernetes.io/component" = "tunnel";
        "app.kubernetes.io/instance" = "primary";
        "app.kubernetes.io/name" = name;
      };

      data."config.yaml" = configContent;
    };
  };
}
