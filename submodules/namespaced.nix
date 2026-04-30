{
  config,
  kubenix,
  lib,
  name,
  args,
  ...
}: {
  imports = with kubenix.modules; [submodule k8s helm];

  options.submodule.args = {
    kubernetes = lib.mkOption {
      description = "Kubernetes config to be applied to a specific namespace";
      type = lib.types.attrs;
      default = {};
    };
  };

  config = {
    submodule = {
      name = "namespaced";
      passthru.kubernetes.objects = config.kubernetes.objects ++ (config.kubernetes.helm.objects or []);
    };

    kubernetes = lib.mkMerge [
      {namespace = name;}
      {resources.namespaces.${name} = {};}
      {
        helm.releases =
          lib.mapAttrs (
            _releaseName: _releaseConfig: {namespace = name;}
          )
          (args.kubernetes.helm.releases or {});
      }

      args.kubernetes
    ];
  };
}
