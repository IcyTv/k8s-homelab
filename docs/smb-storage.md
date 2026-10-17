# SMB storage reconciliation

Audiobookshelf and Paperless use separate Flux storage Kustomizations because
PersistentVolumes are cluster-scoped. Their application Kustomizations keep
namespace-restricted service accounts and depend on their storage Kustomizations.
Paperless's application service account also has a namespace-scoped role for
its Traefik Middleware.

Both storage Kustomizations depend on `smb`. Their SMB PVs reference the shared
`flux-system/storagebox-smb` Secret, managed and decrypted by Flux. Do not inspect
or decrypt credentials for routine troubleshooting. Mount success or failure
can validate access without exposing secret contents.

SMB PVs use `Retain`: changing a CSI secret reference still requires planned
PV recreation, since that reference is immutable. Stop consumers and suspend
their Flux application and storage Kustomizations before recreating explicitly
approved PV/PVC pairs. Preserve the source, subdirectory, volume handle, and
mount options. Never delete local config/database/metadata claims during an
SMB-reference migration, or remove remote files.

Hetzner's main-account SMB share is `backup`; subaccounts use the subaccount
username as the share name and are rooted at their configured directory.
`mount error(13)` can indicate credentials, SMB access settings, or share/path
permissions. Confirm account/share configuration with the operator; do not
expose credentials in commands or diagnostic output.

All live operations for this deployment must explicitly use
`--kubeconfig ./kubeconfig.hetzner.yaml`. The default kubeconfig is another cluster.

## SELinux on Hetzner's Rocky Linux node

SELinux must remain enforcing. Container access to the driver's `cifs_t` mounts
requires the standard node policy boolean:

```sh
sudo setsebool -P virt_use_samba on
getsebool virt_use_samba
```

Apply this during provisioning of each SELinux-enforcing worker that hosts SMB
consumers. It permits SMB access for the node's virtualization/container SELinux
domains; it does not grant Unix permissions or bypass SMB authentication.
Do not make application pods privileged or disable SELinux to work around this.
A privileged diagnostic mount may succeed while an ordinary container is denied
by this policy, even with identical UID/GID settings.
