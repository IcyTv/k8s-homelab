{kubenix, ...}: let
  version = "39.0.8";
in {
  kubernetes.helm.releases.traefik = {
    chart = kubenix.lib.helm.fetch {
      inherit version;
      repo = "https://helm.traefik.io/traefik";
      chart = "traefik";
      sha256 = "pXQOVC70PKdNyqbRPaw31mjSsYhlPT7GsCDI64I1oys=";
    };

    # includeCRDs = true;

    values = {
      providers = {
        kubernetesCRD = {
          enabled = true;
          allowCrossNamespace = true;
        };
        kubernetesIngress.enabled = true;
      };

      ports = {
        web.http = {};
      };

      service.type = "LoadBalancer";
    };
  };
}
