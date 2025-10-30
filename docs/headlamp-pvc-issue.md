# Headlamp PersistentVolumeClaim Issue

The `headlamp` Helm chart (version `0.36.0`) does not correctly use the `persistentVolumeClaim` when it is enabled in the `values.yaml` file.

When `persistentVolumeClaim.enabled` is set to `true`, the Helm chart creates a `PersistentVolumeClaim`, but the `Deployment` does not use it. Instead, it uses an `emptyDir` volume for the `plugins-dir`.

This causes the `HelmRelease` to time out, because it waits for the `PersistentVolumeClaim` to be bound, but it never is.

As a workaround, the `persistentVolumeClaim` has been disabled in the `apps/headlamp/helmrelease.yaml` file. This allows the `HelmRelease` to become healthy, but it means that the plugins will not be persisted.

To fix this issue, the `headlamp` Helm chart needs to be updated to correctly use the `PersistentVolumeClaim` when it is enabled.
