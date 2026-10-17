# Paperless signing image

Upstream `BoBBer446/Paperless-Sign-Service` documents a local Docker build and
does not currently publish a usable container image. The homelab workflow
`.github/workflows/paperless-sign-image.yaml` builds a pinned upstream commit,
smoke-tests both `/api/health` and `/`, then publishes
`ghcr.io/icytv/paperless-sign-service:build-N` on changes to the build inputs on
`hetzner`. Pull requests build and test without publishing. Builds target the
current Hetzner deployment's linux/amd64 architecture.

The build uses GitHub's short-lived `GITHUB_TOKEN`; no cluster credentials,
SOPS keys, or runtime secrets are involved. Only upstream `requirements.txt`,
`app/`, and `LICENSE` are copied. In particular, upstream `data/` must never be
included: it may contain profile tokens and encryption keys.

Renovate tracks:

- `images/paperless-sign-service/upstream.sha` using `git-refs` for upstream
  `main`. These updates require review; merging one triggers a new build.
- The versioned Python base images through the Dockerfile manager.
- Numbered `build-N` deployment image tags through the Kubernetes manager with
  a custom versioning rule.

After the first publish, GitHub may require a one-time visibility change in
the package settings to **Public** before Kubernetes can pull anonymously:
https://github.com/users/IcyTv/packages/container/paperless-sign-service/settings
Do not add a long-lived registry credential to the cluster just to pull this
public application. Check anonymous pull access before updating the deployment.

Use a successfully published numbered tag in the deployment, not `latest`.
The first deployment can be updated manually after the initial build passes;
subsequent builds are detected by Renovate. Re-running a workflow reuses its
numbered tag, so prefer a new build-input commit for a new image version.
