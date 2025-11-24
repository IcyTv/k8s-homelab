# Flux Image Automation

This repository uses Flux Image Automation to keep selected application images up-to-date automatically by committing tag changes to the Git repo.

## Components Added

- `ImageRepository`: Watches a container registry for tags.
- `ImagePolicy`: Selects the latest acceptable tag based on filters.
- `ImageUpdateAutomation`: Scans manifests under `./apps` and updates image fields annotated with policy markers.

## Current Automated Images

| App            | Image                                  | Policy Type | Tag Pattern                          |
|----------------|----------------------------------------|-------------|--------------------------------------|
| audiobookshelf | `ghcr.io/advplyr/audiobookshelf`       | Semver      | `^([0-9]+\.[0-9]+\.[0-9]+)$`        |
| cloudflared    | `cloudflare/cloudflared`               | Alphabetical (desc) | `^([0-9]{4}\.[0-9]+\.[0-9]+)$` |
| homeassistant  | `ghcr.io/home-assistant/home-assistant`| Semver      | `^([0-9]{4}\.[0-9]+\.[0-9]+)$`      |

## How It Works

1. Flux polls the registries (`interval: 1h`).
2. Policies resolve the latest tag that matches filters.
3. Automation checks every hour, updates annotated image lines, and commits with message template.
4. Flux Git reconciliation applies the new manifests.

## Annotating Additional Images

For each deployment or HelmRelease you want automated:

1. Create (or reuse) an `image-automation.yaml` inside the app directory (e.g. `apps/<app>/image-automation.yaml`):
   ```yaml
   apiVersion: image.toolkit.fluxcd.io/v1beta2
   kind: ImageRepository
   metadata:
     name: myapp
     namespace: flux-system
   spec:
     image: ghcr.io/org/myapp
     interval: 1h
   ```
2. Add an `ImagePolicy` selecting tags (semver or alphabetical):
   ```yaml
   apiVersion: image.toolkit.fluxcd.io/v1beta2
   kind: ImagePolicy
   metadata:
     name: myapp
     namespace: flux-system
   spec:
     imageRepositoryRef:
       name: myapp
     filterTags:
       pattern: '^([0-9]+\.[0-9]+\.[0-9]+)$'
       extract: '$1'
     policy:
       semver:
         range: '>=0.0.0'
   ```
3. Annotate the image line in the manifest you want updated:
   ```yaml
   image: ghcr.io/org/myapp:1.2.3 # {"$imagepolicy": "flux-system:myapp"}
   ```
4. Reference the new file from the app's `kustomization.yaml` so Flux applies it alongside the workloads.
5. Ensure the path containing the manifest is under `./apps` (already covered by automation `path: ./apps`).
6. Commit the changes. Flux will handle future updates.

## Notes

- Avoid using floating tags like `latest` or `stable`; automation requires a concrete tag to start from that matches the policy pattern.
- For Helm charts: You can annotate container images inside rendered YAML (if you vendor them) or manage chart version bumps separately. Image automation does not alter chart version fields.
- If a tag format changes upstream, update `filterTags.pattern` accordingly.
- Use `semver` policy when upstream publishes proper semantic versions; otherwise fall back to `alphabetical`.

## Troubleshooting

- Policy shows no tag: Confirm the pattern matches available tags; temporarily remove `filterTags` to list all.
- Automation not committing: Check Flux logs for `image-update-automation` controller and ensure the Git write key (`flux-system` secret) has push access.
- Wrong tag selected: Adjust the policy type (`semver` vs `alphabetical`) or tighten the regex.

## Extending

- For Helm-based apps (e.g. authentik, traefik) consider whether you want to override the chart-provided image tags; chart upgrades may already roll these images forward. If you decide to automate them, add the relevant `values.image.repository/tag` fields and annotate those entries the same way as Deployments.

---
Created by Flux automation setup.
