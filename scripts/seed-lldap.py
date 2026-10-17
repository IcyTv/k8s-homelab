#!/usr/bin/env python3
"""
Seeds LLDAP with default groups (admins, cluster-admins, users, 2fa) and the initial user.
Reads passwords securely from ~/.local/state/authelia/credentials.txt.
"""
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.request

KUBECONFIG = pathlib.Path(__file__).resolve().parent.parent / "kubeconfig.hetzner.yaml"

def read_credentials():
    xdg_state = os.environ.get("XDG_STATE_HOME") or str(pathlib.Path.home() / ".local" / "state")
    creds_path = pathlib.Path(xdg_state) / "authelia" / "credentials.txt"
    if not creds_path.exists():
        sys.exit(f"Error: Credentials file not found at {creds_path}")
    
    text = creds_path.read_text()
    admin_pwd = ""
    user_pwd = ""
    
    in_lldap_section = False
    in_user_section = False
    
    for line in text.splitlines():
        if "LLDAP Admin Credentials:" in line:
            in_lldap_section = True
            in_user_section = False
        elif "User Credentials:" in line:
            in_lldap_section = False
            in_user_section = True
        elif line.startswith("Password:") and in_lldap_section:
            admin_pwd = line.split(":", 1)[1].strip()
        elif line.startswith("Password:") and in_user_section:
            user_pwd = line.split(":", 1)[1].strip()
            
    if not admin_pwd or not user_pwd:
        sys.exit("Error: Could not extract admin or user passwords from credentials file")
    return admin_pwd, user_pwd

def main():
    admin_pwd, user_pwd = read_credentials()
    print("1/4 Checking LLDAP pod status...")
    
    # Check if lldap pod is running
    cmd = ["kubectl", f"--kubeconfig={KUBECONFIG}", "-n", "lldap", "get", "pods", "-l", "app.kubernetes.io/name=lldap", "-o", "jsonpath={.items[0].metadata.name}"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        sys.exit("LLDAP pod is not running yet. Please wait until LLDAP is deployed.")
    pod_name = r.stdout.strip()

    print(f"2/4 Port-forwarding to LLDAP pod ({pod_name})...")
    port_forward = subprocess.Popen(
        ["kubectl", f"--kubeconfig={KUBECONFIG}", "-n", "lldap", "port-forward", f"pod/{pod_name}", "17170:17170"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    time.sleep(2)

    try:
        url = "http://127.0.0.1:17170"
        # 1. Login as admin
        login_data = json.dumps({"username": "admin", "password": admin_pwd}).encode()
        req = urllib.request.Request(f"{url}/auth/simple/login", data=login_data, headers={"Content-Type": "application/json"})
        resp = urllib.request.urlopen(req, timeout=5)
        token = json.loads(resp.read().decode())["token"]
        auth_header = {"Content-Type": "application/json", "Authorization": f"Bearer {token}"}

        def gql(query, variables=None):
            payload = json.dumps({"query": query, "variables": variables or {}}).encode()
            r = urllib.request.Request(f"{url}/api/graphql", data=payload, headers=auth_header)
            return json.loads(urllib.request.urlopen(r, timeout=5).read().decode())

        print("3/4 Creating default groups (admins, cluster-admins, users, 2fa)...")
        existing_groups = {g["displayName"]: g["id"] for g in gql("{ groups { id displayName } }")["data"]["groups"]}
        
        for g_name in ["admins", "cluster-admins", "users", "2fa"]:
            if g_name not in existing_groups:
                res = gql("mutation createGroup($name: String!) { createGroup(name: $name) { id } }", {"name": g_name})
                print(f"  + Group '{g_name}' created.")
            else:
                print(f"  = Group '{g_name}' already exists.")

        # Re-fetch groups map
        existing_groups = {g["displayName"]: g["id"] for g in gql("{ groups { id displayName } }")["data"]["groups"]}

        print("4/4 Creating and configuring user 'michael'...")
        existing_users = [u["id"] for u in gql("{ users { id } }")["data"]["users"]]
        if "michael" not in existing_users:
            user_input = {
                "id": "michael",
                "email": "michael.finger@icytv.de",
                "displayName": "Michael Finger",
                "firstName": "Michael",
                "lastName": "Finger"
            }
            gql("mutation createUser($user: CreateUserInput!) { createUser(user: $user) { id } }", {"user": user_input})
            print("  + User 'michael' created.")
        else:
            print("  = User 'michael' already exists.")

        # Set user password via lldap_set_password inside pod
        set_pwd_cmd = [
            "kubectl", f"--kubeconfig={KUBECONFIG}", "-n", "lldap", "exec", f"pod/{pod_name}", "--",
            "/app/lldap_set_password",
            "--base-url", "http://localhost:17170",
            "--admin-username", "admin",
            "--admin-password", admin_pwd,
            "--username", "michael",
            "--password", user_pwd
        ]
        subprocess.run(set_pwd_cmd, check=True, stdout=subprocess.DEVNULL)
        print("  + Password set for 'michael'.")

        # Add michael to groups: admins, cluster-admins, users
        user_info = gql('{ user(userId: "michael") { groups { displayName } } }')["data"]["user"]
        user_group_names = [g["displayName"] for g in user_info.get("groups", [])]

        for target_group in ["admins", "cluster-admins", "users"]:
            if target_group not in user_group_names:
                g_id = existing_groups[target_group]
                gql("mutation addUserToGroup($userId: String!, $groupId: Int!) { addUserToGroup(userId: $userId, groupId: $groupId) { ok } }",
                    {"userId": "michael", "groupId": g_id})
                print(f"  + Added 'michael' to group '{target_group}'.")

        print("LLDAP seeding successfully completed.")

    finally:
        port_forward.terminate()

if __name__ == "__main__":
    main()
