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
        # Tools installed in the shell
        buildInputs = with pkgs; [
          kubectl
          fluxcd
          kubernetes-helm # Often needed alongside Flux
        ];

        # Shell hook to handle cluster connection/env vars
        shellHook = ''
          echo "❄️ Welcome to the Kubernetes dev shell"

          # Point to a local kubeconfig if it exists in this directory
          # or use the default ~/.kube/config
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
