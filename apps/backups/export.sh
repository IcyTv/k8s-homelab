#!/bin/sh
# Publish an already-completed native HA archive, then ask VolSync to upload it.
# Restic scheduling/retention/restoration remain the operator's responsibility.
set -eu
set -o pipefail
umask 077

api=https://kubernetes.default.svc
sa=/var/run/secrets/kubernetes.io/serviceaccount
resource=/apis/volsync.backube/v1alpha1/namespaces/homeassistant/replicationsources/homeassistant
printf 'Authorization: Bearer %s\n' "$(cat "$sa/token")" > /tmp/api-header

request() {
    curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
        --cacert "$sa/ca.crt" -H @/tmp/api-header "$@"
}

notify() {
    curl --fail --silent --show-error --connect-timeout 5 --max-time 15 \
        -H 'Content-Type: application/json' \
        --data '{"message":"Home Assistant offsite backup failed or its native archive is older than 36 hours. Check the backups Job and VolSync ReplicationSource in the homeassistant namespace."}' \
        "http://homeassistant.homeassistant.svc.cluster.local:8123/api/webhook/$(cat /notifications/HA_BACKUP_WEBHOOK_ID)" >/dev/null || \
        echo 'WARNING: Could not deliver the Home Assistant backup notification' >&2
}

finish() {
    code=$?
    trap - EXIT
    if [ "$code" -ne 0 ]; then notify; fi
    exit "$code"
}
trap finish EXIT

status=$(request -w '%{http_code}' -o /tmp/source.json "$api$resource") || [ "$status" = 404 ]
[ "$status" = 200 ] || [ "$status" = 404 ] || exit 1
if [ "$status" = 200 ] && jq -e '.status.conditions[]? | select(.type == "Synchronizing" and .status == "True")' /tmp/source.json >/dev/null; then
    echo 'An upload is still active; refusing to replace its source archive' >&2
    exit 1
fi

# The BackupStore records a backup only after its archive has been written and
# uploads to native backup agents have finished (HA 2026.10.4).
latest=
backup_id=
for archive in /source/backups/*.tar; do
    [ -f "$archive" ] || continue
    metadata=$(tar -xOf "$archive" ./backup.json 2>/dev/null) || continue
    id=$(printf '%s' "$metadata" | jq -er 'select(.homeassistant.exclude_database == false) | .slug') || continue
    case "$id" in ''|*[!a-zA-Z0-9_-]*) continue ;; esac
    jq -e --arg id "$id" '.data.backups[] | select(.backup_id == $id and ((.failed_addons // []) | length) == 0 and ((.failed_agent_ids // []) | length) == 0 and ((.failed_folders // []) | length) == 0)' /source/.storage/backup >/dev/null || continue
    if [ -z "$latest" ] || [ "$archive" -nt "$latest" ]; then
        latest=$archive
        backup_id=$id
    fi
done
[ -n "$latest" ] || { echo 'No completed, database-inclusive native backup found' >&2; exit 1; }
age=$(( $(date +%s) - $(stat -c %Y "$latest") ))
[ "$age" -ge 0 ] && [ "$age" -lt 129600 ] || { echo 'Latest native backup is stale or has an invalid timestamp' >&2; exit 1; }

# Apply the versioned Source template without a second GitOps writer owning its
# trigger field. On first use it is created ONLY after the export exists.
if [ "$status" = 200 ] && jq -e --arg prefix "$backup_id-" '(.status.lastManualSync // "" | startswith($prefix)) and .status.latestMoverStatus.result == "Successful"' /tmp/source.json >/dev/null; then
    jq '{spec:.spec}' /scripts/replicationsource.json > /tmp/desired.json
    request -X PATCH -H 'Content-Type: application/merge-patch+json' --data-binary @/tmp/desired.json "$api$resource" >/dev/null
    echo 'Latest native archive is fresh and already uploaded successfully'
    exit 0
fi

# The source has no independent schedule: this Job is the only publisher/trigger.
# No replacement can happen while a mover is scanning the export volume.
cp "$latest" /export/.archive.partial
mv /export/.archive.partial /export/homeassistant.tar
cd /export
sha256sum homeassistant.tar > /export/.checksum.partial
mv /export/.checksum.partial /export/SHA256SUMS
printf '%s\n' "$backup_id" > /export/backup-id

trigger="$backup_id-$(date +%s)"
jq --arg id "$trigger" '.spec.trigger.manual = $id' /scripts/replicationsource.json > /tmp/desired.json
if [ "$status" = 404 ]; then
    request -X POST -H 'Content-Type: application/json' --data-binary @/tmp/desired.json "$api${resource%/homeassistant}" >/dev/null
else
    jq '{spec:.spec}' /tmp/desired.json > /tmp/trigger.json
    request -X PATCH -H 'Content-Type: application/merge-patch+json' --data-binary @/tmp/trigger.json "$api$resource" >/dev/null
fi
echo 'Completed native archive published; waiting for VolSync upload'
for attempt in $(seq 1 180); do
    request "$api$resource" > /tmp/source.json
    if [ "$(jq -r '.status.lastManualSync // ""' /tmp/source.json)" = "$trigger" ] && [ "$(jq -r '.status.latestMoverStatus.result // ""' /tmp/source.json)" = Successful ]; then
        echo 'Verified native archive uploaded successfully through VolSync'
        exit 0
    fi
    sleep 5
done
echo 'VolSync did not complete the upload within 15 minutes' >&2
exit 1
