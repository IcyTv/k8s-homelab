_: let
  name = "tailscale";
  version = "stable";
  state_dir = "/var/lib/tailscale";
in {
  kubernetes.resources = {
    deployments.tailscale = {
      spec = {
        replicas = 1;
        selector.matchLabels.app = name;

        template = {
          metadata.labels.app = name;

          spec = {
            hostNetwork = true;
            dnsPolicy = "ClusterFirstWithHostNet";

            containers.tailscale = {
              image = "tailscale/tailscale:${version}";
              imagePullPolicy = "Always";

              securityContext = {
                privileged = true;
                capabilities = {
                  add = ["NET_ADMIN" "NET_RAW"];
                  drop = ["ALL"];
                };
              };

              env = [
                {
                  name = "TS_STATE_DIR";
                  value = state_dir;
                }
                {
                  name = "TS_USERSPACE";
                  value = "false";
                }
                {
                  name = "TS_ACCEPT_DNS";
                  value = "false";
                }
                {
                  name = "TS_ROUTES";
                  value = "192.168.1.0/24,10.42.0.0/16,10.43.0.0/16";
                }
                {
                  name = "TS_EXTRA_ARGS";
                  value = "--advertise-exit-node=true --accept-routes=false";
                }
                {
                  name = "TS_HOSTNAME";
                  value = "server";
                }
                {
                  name = "POD_NAME";
                  valueFrom.fieldRef = {
                    apiVersion = "v1";
                    fieldPath = "metadata.name";
                  };
                }
                {
                  name = "POD_UID";
                  valueFrom.fieldRef = {
                    apiVersion = "v1";
                    fieldPath = "metadata.uid";
                  };
                }
              ];

              volumeMounts = {
                "${state_dir}".name = "tailscale-state";
                "/dev/net/tun".name = "dev-net-tun";
              };

              resources = {
                requests = {
                  cpu = "25m";
                  memory = "64Mi";
                };
                limits = {
                  cpu = "200m";
                  memory = "256Mi";
                };
              };
            };

            volumes = {
              "tailscale-state" = {
                name = "tailscale-state";
                persistentVolumeClaim.claimName = "tailscale-state";
              };
              "dev-net-tun" = {
                name = "dev-net-tun";
                hostPath = {
                  path = "/dev/net/tun";
                  type = "CharDevice";
                };
              };
            };
          };
        };
      };
    };

    persistentVolumeClaims.tailscale-state.spec = {
      accessModes = ["ReadWriteOnce"];
      resources.requests.storage = "1Gi";
    };
  };
}
