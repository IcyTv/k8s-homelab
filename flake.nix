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
          yq
          kubeconform
          kustomize
          cmctl
        ];

        shellHook = ''
          echo "❄️ Welcome to the Kubernetes dev shell"

          if [ -f "./kubeconfig.yaml" ]; then
            export KUBECONFIG="$PWD/kubeconfig.yaml"
            echo "📍 Using local project kubeconfig"
          fi

          if [ -f "$HOME/.keys/k8s-age.txt" ]; then
            export SOPS_AGE_KEY_FILE="$HOME/.keys/k8s-age.txt"
            echo "🔐 SOPS configured with AGE key"
          else
            echo "⚠️ Warning: No AGE key found for SOPS. Encrypted secrets may not be accessible."
            echo "Run \'kubectl get secret sops-age -n flux-system -o jsonpath='{.data.age\.agekey}' | base64 -d > $HOME/.keys/k8s-age.txt\' to get the key"
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
