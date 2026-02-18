{
  description = "Kubernetes and FluxCD DevShell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    utils,
  }:
    utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          kubectl
          fluxcd
          kubernetes-helm
          sops
          age
        ];

        shellHook = ''
          echo "❄️ Welcome to the Kubernetes dev shell"

          if [ -f "./kubeconfig.yaml" ]; then
            export KUBECONFIG="$PWD/kubeconfig.yaml"
            echo "📍 Using local project kubeconfig"
          fi

          # Optional: Check if we can reach the cluster
          if kubectl cluster-info >/dev/null 2>&1; then
            echo "✅ Connected to cluster: $(kubectl config current-context)"
          else
            echo "⚠️ Warning: No active cluster connection detected."
          fi

          echo "Flux version: $(flux --version)"
        '';
      };
    });
}
