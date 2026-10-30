# Homeserver backups

Home Assistant creates encrypted native daily archives, including Recorder's
database, and retains three locally. VolSync uploads completed archives to the
Storage Box using Restic encryption over Rclone's SFTP transport. The operator
and snapshot-controller prerequisite are managed by Flux on branch `home` only.

The exporter CronJob checks hourly for a new completed native archive, copies it
to `homeassistant-backup-export`, and submits the versioned
`replicationsource.json` template to VolSync with a unique manual trigger. The
template is deliberately not applied independently: VolSync starts its first
sync immediately, even with a manual trigger. Publication must happen first.
Restic scheduling, repository maintenance, and restoration are not implemented
by a custom Python controller.

Source archives are selected only when Home Assistant's BackupStore records
them as completed without component/agent failures. This small shell integration
is checked against Home Assistant 2026.10.4; check the BackupStore schema when
upgrading Home Assistant. It never copies the live SQLite database directly.

The exporter refuses to replace an archive while VolSync is synchronizing, and
there is no independent mover schedule. Failed uploads are retried with a new
manual token. A stale native archive (36 hours) is a failure, not a fresh backup.

## Prepare credentials

1. Restrict the Storage Box subaccount to `backups/homeserver`, enable external
   access, and enable SSH support on port 23.
2. Generate a dedicated SSH key locally. Authorize its public key in the
   subaccount's `.ssh/authorized_keys` using OpenSSH format; do not reuse the main
   account's credentials.
3. Edit `secret.yaml` with SOPS. Verify the SSH server fingerprint against
   Hetzner's published fingerprints before adding the known-hosts entry.
4. Save the Restic password separately in your password manager for recovery.
5. Encrypt before staging or committing:

   ```sh
   sops --encrypt --in-place apps/backups/secret.yaml
   ```

The repository's SOPS rules encrypt `stringData`. Never paste decrypted values
into chat or logs, and never commit the plaintext file. The Secret is namespaced
to `homeassistant`; future apps need namespaced credentials and separate Restic
repository paths. They may initially reuse the subaccount and SSH identity.

`RESTIC_REPOSITORY` is `rclone:storagebox:homeassistant`. The `RCLONE_CONFIG_*`
settings enable SFTP with strict known-host verification and explicitly negotiate
the verified ED25519 host key. Secret mounts are under `/mnt/ssh` using VolSync's
supported `moverVolumes`. No SMB share, S3 gateway, or VPS service is involved.

Two independent encryption passwords are needed: `RESTIC_PASSWORD` protects the
repository, and `HA_BACKUP_PASSWORD` decrypts the native archive. Keep these in a
password manager/Home Assistant emergency kit as well as in SOPS, and keep the
SOPS age recovery key outside this cluster.

## Repository layout

Paths are relative to the subaccount's restricted root; do not repeat
`backups/homeserver`. Use a separate Restic repository per application:

```text
backups/homeserver/    # directory configured in Hetzner, invisible parent to subaccount
  .ssh/
  homeassistant/      # planned first Restic repository
  another-app/        # future independent Restic repository
```

## Scheduling, status, and failures

The native backup schedule/three-copy retention is owned by Home Assistant's UI,
not rewritten by Flux. Offsite retention is 7 daily, 4 weekly, and 6 monthly
snapshots, with pruning every seven days. Because native archives are encrypted
and compressed, deduplication between different native archives is limited.
The `homeassistant-backup-check` CronJob reads and checks all repository data
every Sunday at 07:00 Europe/Berlin, reporting errors through the same webhook.
With the current native settings, Home Assistant starts daily around 04:45 with
up to one hour of jitter. The hourly exporter therefore does not rely on an
assumed fixed native completion time.

Initial validation on 2026-10-30 passed: a disposable SFTP round-trip (content,
hidden files, modes, ownership, SQLite), a real offsite archive restore/decryption,
integrity checks for both restored SQLite databases, and isolated Home Assistant
2026.10.4 startup with HTTP 200. The restored test instance had automations
disabled, no Zigbee device, and verified external network blocking. A full
`restic check --read-data` of the initial repository also passed.

Check the `homeassistant-backup-export` CronJob and the `homeassistant`
ReplicationSource in namespace `homeassistant`. The exporter has narrowly scoped
permission to create Sources and get/patch only its named Source; it cannot stop
Home Assistant or change Flux. Its live configuration mount is read-only.

Failures and stale archives send an internal webhook to Home Assistant, which
creates a persistent notification. Native backup failures also create one.
The package is mounted at `/config/k8s_packages/backups.yaml`; Home Assistant's
configuration must include:

```yaml
homeassistant:
  packages: !include_dir_named k8s_packages
```

Do not add a duplicate `homeassistant:` mapping to an existing configuration.
The webhook ID comes from a single Secret key environment variable. The
NetworkPolicy permits only exporter-labelled pods to call Home Assistant.
These are in-app notifications, not independent outage alerts: if Home Assistant,
the node, or the whole cluster is down, it cannot notify. An external dead-man
monitor/mobile notification destination remains a separate operational choice.

## Recovery and restore drills

1. Recover the SOPS age key, repository credentials, Restic password, and native
   backup password independently of the failed machine.
2. Restore using a VolSync `ReplicationDestination` into a **different empty
   PVC**. Reuse the Source's repository/SSH configuration and `copyMethod: Direct`.
   Never select the production configuration PVC as the destination.
3. Verify `SHA256SUMS` against the restored `homeassistant.tar`.
4. Decrypt/import the native archive with supported Home Assistant backup tooling
   and `HA_BACKUP_PASSWORD`. Validate SQLite integrity and expected configuration.
5. Test application startup in isolation: no Zigbee device, external network, or
   active automations that can operate real devices. Use the archived HA version.

Only migrate the OS after a real offsite restore drill passes. During migration,
restore the configuration before starting the production Deployment and re-add
the package include if restoring an older archive that predates this setup.
