# Cluster Issuer manifests

This directory hosts the cert-manager resources for Let’s Encrypt. The `ClusterIssuer` expects a Kubernetes `Secret` named `cloudflare-api-token` in the `cert-manager` namespace containing the Cloudflare API token under the key `api-token`.

To manage the secret via Sealed Secrets, generate or rotate it with:

```bash
./scripts/create-sealed-secret.sh cert-manager cloudflare-api-token api-token="<cloudflare-api-token>"
```

The script writes `cloudflare-api-token.sealedsecret.yaml` into this folder. Commit the generated file to keep the token under GitOps control. Whenever the token changes, rerun the script with the new value and commit the update.
