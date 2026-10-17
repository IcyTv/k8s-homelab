#!/usr/bin/env python3
"""
Prints the latest 2FA identity verification code from Authelia's notifications log.
"""
import pathlib
import re
import subprocess
import sys

KUBECONFIG = pathlib.Path(__file__).resolve().parent.parent / "kubeconfig.hetzner.yaml"

def main():
    cmd = [
        "kubectl", f"--kubeconfig={KUBECONFIG}", "-n", "authelia", "exec", "deployment/authelia", "--",
        "cat", "/data/notifications.txt"
    ]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"Error reading notifications: {r.stderr}")

    lines = r.stdout.strip().splitlines()
    if not lines:
        print("No notifications found.")
        return

    # Find any standalone 8-character alphanumeric token in the notification text
    matches = re.findall(r"\n\n([A-Z0-9]{8})\n\n", r.stdout)
    if matches:
        print(f"Latest Authelia Verification Code: {matches[-1]}")
    else:
        print("Full notifications log:")
        print(r.stdout[-500:])

if __name__ == "__main__":
    main()
