# Internal Authentik DNS

`apps/base/coredns-custom.yaml` configures K3s CoreDNS to rewrite only
`auth.icytv.de` to `traefik.traefik.svc.cluster.local`. Kubernetes service
discovery supplies the current Traefik service IP, so no fixed IP or per-app
`hostAliases` is needed. The exact rewrite also restores the original name in
DNS responses.

This keeps pod-to-Authentik OIDC requests away from Cloudflare's browser
challenges. Applications still use `https://auth.icytv.de`, preserving HTTPS
certificate verification, the public OIDC issuer, and browser redirects.
Public DNS and other domains are unchanged.

The ConfigMap is included in the Flux `base` Kustomization. It uses K3s's
supported `*.override` imports; do not edit the K3s-managed Corefile.
Clusters using these shared manifests must have the same Traefik service name
and namespace, K3s CoreDNS custom imports, and the `cluster.local` cluster domain.
Pods must use cluster DNS (normally `dnsPolicy: ClusterFirst`). This does not
change host/node DNS resolution.

## Validation on Hetzner

Always specify `--kubeconfig ./kubeconfig.hetzner.yaml`; the default kubeconfig
targets a different cluster.

From the Headlamp Node.js sidecar, check DNS directly (ignoring `/etc/hosts`):

```sh
kubectl --kubeconfig ./kubeconfig.hetzner.yaml -n headlamp exec deployment/headlamp -c headlamp-plugin -- node -e 'const d=require("dns").promises; Promise.all([d.resolve4("auth.icytv.de"),d.resolve4("traefik.traefik.svc.cluster.local")]).then(console.log)'
```

Both results should match. Check HTTPS without disabling certificate validation:

```sh
kubectl --kubeconfig ./kubeconfig.hetzner.yaml -n headlamp exec deployment/headlamp -c headlamp-plugin -- node -e 'require("https").get("https://auth.icytv.de/application/o/k3s/.well-known/openid-configuration",r=>{console.log(r.statusCode);r.pipe(process.stdout)}).on("error",console.error)'
```

Expect HTTP 200 and issuer `https://auth.icytv.de/application/o/k3s/`.
ConfigMap projection and CoreDNS reload can take a few minutes. Inspect CoreDNS
logs for reload errors if DNS does not update. Remove the `authentik.override`
key from the ConfigMap to undo the rewrite (public Cloudflare DNS then applies).

References:
- https://docs.k3s.io/advanced#coredns-custom-configuration-imports
- https://coredns.io/plugins/rewrite/
