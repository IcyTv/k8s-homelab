{...}: let
  name = "audiobookshelf";
  version = "2.33.2";
in {
  kubernetes.resources = {
    deployments.audiobookshelf.spec = {
      replicas = 1;
      selector.matchLabels.app = name;

      template = {
        metadata.labels.app = name;

        spec = {
          containers.audiobookshelf = {
            image = "ghcr.io/avdplyr/audiobookshelf:${version}";

            ports = [
              {
                name = "http";
                containerPort = 80;
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
              "/metadata".name = "metadata";
              "/audiobooks".name = "audiobooks";
            };
          };

          volumes = {
            config.hostPath = {
              path = "/home/michael/media/config";
              type = "Directory";
            };
            metadata.hostPath = {
              path = "/home/michael/media/metadata";
              type = "Directory";
            };
            audiobooks.hostPath = {
              path = "/home/michael/media/audiobooks";
              type = "Directory";
            };
          };
        };
      };
    };
  };
}
