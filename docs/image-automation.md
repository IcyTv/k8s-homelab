# Dependency Automation

This repository uses Renovate to update Kubernetes container images, Flux
`HelmRelease` chart versions, Flux itself, and Nix flake inputs. Renovate opens
pull requests, and Flux applies changes after they reach `main`.

## Update Policy

- Patch releases are merged automatically after they are at least three days
  old and the manifest validation workflow passes.
- Minor and major releases remain open for review.
- Authentik upgrades always remain open for review because releases can require
  ordered database migrations.
- Nix lock-file maintenance runs weekly.
- Image digests are not pinned, keeping the manifests readable and avoiding
  duplicate tag and digest update pull requests.

The policy and dependency discovery rules live in `renovate.json5`. The
validation workflow is `.github/workflows/validate.yaml` and runs
`scripts/validate.sh` inside the repository's Nix development shell.

## Coverage

Renovate scans YAML under `apps/` with both its Kubernetes and Flux managers.
This covers ordinary workload images and charts referenced by `HelmRelease`
resources. Its Flux manager also recognizes
`clusters/main/flux-system/gotk-components.yaml`, and its Nix manager updates
`flake.lock`.

The Headlamp Flux plugin version is discovered with a custom rule because it is
embedded in plugin-manager configuration rather than a standard Kubernetes
image or Helm chart field.

Floating image tags such as `stable` and `latest` cannot produce semantic
version upgrades. Keep those tags only when following the upstream channel is
intentional; use a concrete version when Renovate should propose version bumps.

## Setup

Install the hosted Renovate GitHub App for `IcyTv/k8s-homelab`:

<https://github.com/apps/renovate>

In the Mend portal, set **Dependency Updates (Renovate)** to **Active**. Silent
mode discovers updates but does not create branches, pull requests, or issues.

The committed configuration skips Renovate's onboarding-only mode, so it can
create dependency pull requests after the app has access to the repository.

## Legacy Flux Resources

The unreferenced `image-automation.yaml` files are retained as historical
configuration only. The cluster was bootstrapped without Flux's optional image
reflector and image automation controllers, and no app kustomization includes
those resources. Renovate ignores these files; do not enable both systems for
the same image.
