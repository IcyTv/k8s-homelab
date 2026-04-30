{...}: let
  name = "homeassistant";
  version = "2026.4.4";
  targetPort = 8123;
  probeGet = {
    path = "/";
    port = targetPort;
  };
in {
  kubernetes.resources = {
    persistentVolumeClaims.homeassistant-config.spec = {
      accessModes = ["ReadWriteOnce"];
      storageClassName = "local-storage";
      resources.requests.storage = "5Gi";
      volumeName = "ha-config-pv";
    };

    deployments.homeassistant.spec = {
      replicas = 1;
      strategy.type = "Recreate";
      selector.matchLabels.app = name;

      template = {
        metadata.labels.app = name;

        spec = {
          securityContext = {
            runAsUser = 1000;
            runAsGroup = 1000;
            supplementalGroups = [20 986]; # TODO: parameterize these. Maybe even find them in the system somehow
          };

          containers.homeassistant = {
            image = "ghcr.io/home-assistant/home-assistant:${version}";
            imagePullPolicy = "IfNotPresent";

            securityContext.privileged = true;

            ports = [
              {
                name = "http";
                containerPort = 8123;
                protocol = "TCP";
              }
            ];

            env = [
              {
                name = "TZ";
                value = "Europe/Berlin";
              }
            ];

            volumeMounts = {
              "/config".name = "config";
              "/dev/zigbee".name = "zigbee-usb";
            };

            readinessProbe = {
              httpGet = probeGet;
              initialDelaySeconds = 15;
              periodSeconds = 10;
            };
            livenessProbe = {
              httpGet = probeGet;
              initialDelaySeconds = 120;
              periodSeconds = 15;
            };
          };

          volumes = {
            config.persistentVolumeClaim.claimName = "homeassistant-config";
            "zigbee-usb".hostPath = {
              path = "/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0"; # TODO Parameterize
              type = "CharDevice";
            };
          };
        };
      };
    };

    services.homeassistant.spec = {
      selector.app = name;
      type = "ClusterIP";
      ports = [
        {
          inherit targetPort;
          name = "http";
          port = 80;
          protocol = "TCP";
        }
      ];
    };

    ingresses.homeassistant = {
      metadata.annotations = {
        "traefik.ingress.kubernetes.io/router.entrypoints" = "web";
        "traefik.ingress.kubernetes.io/servoce/serversscheme" = "http";
      };

      spec = {
        ingressClassName = "traefik";
        rules = [
          {
            host = "assistant.icytv.de";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "homeassistant";
                  port.name = "http";
                };
              }
            ];
          }
        ];
      };
    };
  };
}
