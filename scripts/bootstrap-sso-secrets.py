#!/usr/bin/env python3
"""
Generates and SOPS-encrypts all LLDAP, Authelia, and OIDC client secrets.
No secrets or credentials are ever printed to stdout/stderr or sent over chat.
Generated credentials are saved securely to ~/.local/state/authelia/credentials.txt (mode 0600).
"""
import os
import pathlib
import re
import subprocess
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
AUTHELIA_IMAGE = "docker.io/authelia/authelia:4.38.19"
AGE_RE = re.compile(r"age:\s*(age1[a-z0-9]+)")

def get_age_recipient() -> str:
    sops_config = REPO_ROOT / ".sops.yaml"
    if not sops_config.exists():
        sys.exit("Error: .sops.yaml not found")
    match = AGE_RE.search(sops_config.read_text())
    if not match:
        sys.exit("Error: Age recipient key not found in .sops.yaml")
    return match.group(1)

def authelia_cmd(args: list[str]) -> str:
    cmd = ["docker", "run", "--rm", AUTHELIA_IMAGE, "authelia"] + args
    r = subprocess.run(cmd, capture_output=True, check=True)
    return r.stdout.decode()

def generate_random(length: int = 72) -> str:
    out = authelia_cmd(["crypto", "rand", "--length", str(length), "--charset", "rfc3986"])
    return out.strip().splitlines()[-1].strip()

def generate_hash_pair(length: int = 72) -> tuple[str, str]:
    out = authelia_cmd(["crypto", "hash", "generate", "pbkdf2", "--variant", "sha512",
                        "--random", "--random.length", str(length), "--random.charset", "rfc3986"])
    lines = out.strip().splitlines()
    pwd, digest = "", ""
    for line in lines:
        if line.startswith("Random Password:"):
            pwd = line.split(":", 1)[1].strip()
        elif line.startswith("Digest:"):
            digest = line.split(":", 1)[1].strip()
    if not pwd or not digest:
        sys.exit("Error generating PBKDF2 hash pair")
    return pwd, digest

def generate_argon2_pair(length: int = 32) -> tuple[str, str]:
    out = authelia_cmd(["crypto", "hash", "generate", "argon2",
                        "--random", "--random.length", str(length)])
    lines = out.strip().splitlines()
    pwd, digest = "", ""
    for line in lines:
        if line.startswith("Random Password:"):
            pwd = line.split(":", 1)[1].strip()
        elif line.startswith("Digest:"):
            digest = line.split(":", 1)[1].strip()
    if not pwd or not digest:
        sys.exit("Error generating Argon2 pair")
    return pwd, digest

def generate_rsa_keypair(out_dir: pathlib.Path) -> tuple[str, str]:
    cmd = ["docker", "run", "--rm", "-v", f"{out_dir}:/out", AUTHELIA_IMAGE,
           "authelia", "crypto", "pair", "rsa", "generate", "--directory", "/out",
           "--file.private-key", "key.pem", "--file.public-key", "pub.pem"]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
    priv = (out_dir / "key.pem").read_text()
    pub = (out_dir / "pub.pem").read_text()
    (out_dir / "key.pem").unlink()
    (out_dir / "pub.pem").unlink()
    return priv, pub

def encrypt_sops_file(path: pathlib.Path, content: str, age_recipient: str) -> None:
    path.write_text(content)
    cmd = ["sops", "-e", "-i", "--age", age_recipient, str(path)]
    r = subprocess.run(cmd, capture_output=True)
    if r.returncode != 0:
        sys.exit(f"sops encryption failed for {path}: {r.stderr.decode()}")

def main():
    age_key = get_age_recipient()
    print("1/5 Generating cryptographic keys & random secrets...")
    jwt_secret = generate_random(64)
    session_secret = generate_random(64)
    storage_enc_key = generate_random(64)
    oidc_hmac_secret = generate_random(64)

    lldap_jwt_secret = generate_random(64)
    lldap_key_seed = generate_random(64)
    lldap_admin_password = generate_random(32)

    tmp_dir = pathlib.Path("/tmp/opencode/authelia-keygen")
    tmp_dir.mkdir(parents=True, exist_ok=True)
    rsa_priv, rsa_pub = generate_rsa_keypair(tmp_dir)
    tmp_dir.rmdir()

    print("2/5 Generating user credentials...")
    user_pwd, user_hash = generate_argon2_pair(32)

    print("3/5 Generating OIDC client credentials & PBKDF2 digests...")
    headlamp_secret, headlamp_hash = generate_hash_pair(72)
    paperless_secret, paperless_hash = generate_hash_pair(72)
    audiobookshelf_secret, audiobookshelf_hash = generate_hash_pair(72)
    sign_token = generate_random(48)

    # 1. LLDAP secrets
    lldap_dir = REPO_ROOT / "apps" / "lldap"
    lldap_dir.mkdir(parents=True, exist_ok=True)
    lldap_secrets_yaml = f"""apiVersion: v1
kind: Secret
metadata:
  name: lldap-secrets
  namespace: lldap
type: Opaque
stringData:
  jwt-secret: "{lldap_jwt_secret}"
  key-seed: "{lldap_key_seed}"
  admin-password: "{lldap_admin_password}"
"""
    encrypt_sops_file(lldap_dir / "secrets.sops.yaml", lldap_secrets_yaml, age_key)

    # 2. Authelia core secrets
    authelia_dir = REPO_ROOT / "apps" / "authelia"
    authelia_dir.mkdir(parents=True, exist_ok=True)

    authelia_secrets_yaml = f"""apiVersion: v1
kind: Secret
metadata:
  name: authelia-secrets
  namespace: authelia
type: Opaque
stringData:
  jwt-secret: "{jwt_secret}"
  session-secret: "{session_secret}"
  storage-encryption-key: "{storage_enc_key}"
  oidc-hmac-secret: "{oidc_hmac_secret}"
  lldap-admin-password: "{lldap_admin_password}"
  oidc-jwks-key.pem: |
{chr(10).join('    ' + line for line in rsa_priv.strip().splitlines())}
"""
    encrypt_sops_file(authelia_dir / "secrets.sops.yaml", authelia_secrets_yaml, age_key)

    # 3. Headlamp OIDC secret
    headlamp_secret_yaml = f"""apiVersion: v1
kind: Secret
metadata:
  name: oidc-secret
  namespace: headlamp
type: Opaque
stringData:
  OIDC_CLIENT_ID: "CT7sh7bEIljUcAd8PxQjOJiBUflkywbhNJ1ZXaLE"
  OIDC_CLIENT_SECRET: "{headlamp_secret}"
  OIDC_ISSUER_URL: "https://auth.icytv.de/oauth"
"""
    encrypt_sops_file(REPO_ROOT / "apps" / "headlamp" / "oidc-secret.yaml", headlamp_secret_yaml, age_key)

    # 4. Paperless OIDC secret
    paperless_secret_yaml = f"""apiVersion: v1
kind: Secret
metadata:
  name: oidc-secret
  namespace: paperless-ngx
type: Opaque
stringData:
  client-id: "p0C1IEP67fwdvuYwyntruaY6N45hmZrYhVmdnnib"
  client-secret: "{paperless_secret}"
  sign-service-token: "{sign_token}"
"""
    encrypt_sops_file(REPO_ROOT / "apps" / "paperless-ngx" / "oidc-secret.yaml", paperless_secret_yaml, age_key)

    # 5. Write configuration to Authelia configmap
    authelia_config_yaml = f"""apiVersion: v1
kind: ConfigMap
metadata:
  name: authelia-config
  namespace: authelia
data:
  configuration.yml: |
    server:
      address: 'tcp://0.0.0.0:9091/oauth'
    log:
      level: 'info'
    totp:
      issuer: 'icytv.de'
    authentication_backend:
      ldap:
        implementation: 'lldap'
        address: 'ldap://lldap.lldap.svc.cluster.local:3890'
        base_dn: 'DC=icytv,DC=de'
        user: 'UID=admin,OU=people,DC=icytv,DC=de'
        password: '{{{{ secret "/secrets/lldap-admin-password" }}}}'
    access_control:
      default_policy: 'deny'
      rules:
        - domain: 'auth.icytv.de'
          resources:
            - '^/oauth([/?].*)?$'
            - '^/\\\.well-known([/?].*)?$'
          policy: 'bypass'
        - domain: '*.icytv.de'
          subject:
            - 'group:2fa'
          policy: 'two_factor'
        - domain: '*.icytv.de'
          policy: 'one_factor'
    session:
      secret: '{{{{ secret "/secrets/session-secret" }}}}'
      expiration: '12h'
      inactivity: '30m'
      remember_me: '14d'
      cookies:
        - domain: 'icytv.de'
          authelia_url: 'https://auth.icytv.de/oauth'
          default_redirection_url: 'https://cluster.icytv.de'
    regulation:
      max_retries: 5
      find_time: '2m'
      ban_time: '5m'
    storage:
      encryption_key: '{{{{ secret "/secrets/storage-encryption-key" }}}}'
      local:
        path: '/data/db.sqlite3'
    notifier:
      filesystem:
        filename: '/data/notifications.txt'
    identity_validation:
      reset_password:
        jwt_secret: '{{{{ secret "/secrets/jwt-secret" }}}}'
    identity_providers:
      oidc:
        hmac_secret: '{{{{ secret "/secrets/oidc-hmac-secret" }}}}'
        jwks:
          - key_id: 'default'
            algorithm: 'RS256'
            use: 'sig'
            key: {{{{ secret "/secrets/oidc-jwks-key.pem" | mindent 12 "|" | msquote }}}}
        cors:
          endpoints:
            - 'authorization'
            - 'token'
            - 'revocation'
            - 'introspection'
            - 'userinfo'
          allowed_origins:
            - 'https://cluster.icytv.de'
            - 'https://docs.icytv.de'
            - 'https://audiobook.icytv.de'
        authorization_policies:
          headlamp_policy:
            default_policy: 'deny'
            rules:
              - policy: 'two_factor'
                subject: 'group:2fa'
              - policy: 'one_factor'
                subject:
                  - 'group:cluster-admins'
                  - 'group:admins'
          client_policy:
            default_policy: 'one_factor'
            rules:
              - policy: 'two_factor'
                subject: 'group:2fa'
        clients:
          - client_id: 'CT7sh7bEIljUcAd8PxQjOJiBUflkywbhNJ1ZXaLE'
            client_name: 'Headlamp'
            client_secret: '{headlamp_hash}'
            public: false
            authorization_policy: 'headlamp_policy'
            redirect_uris:
              - 'https://cluster.icytv.de/oidc-callback'
            scopes:
              - 'openid'
              - 'profile'
              - 'email'
              - 'groups'
            response_types:
              - 'code'
            grant_types:
              - 'authorization_code'
            token_endpoint_auth_method: 'client_secret_basic'

          - client_id: 'p0C1IEP67fwdvuYwyntruaY6N45hmZrYhVmdnnib'
            client_name: 'Paperless'
            client_secret: '{paperless_hash}'
            public: false
            authorization_policy: 'client_policy'
            redirect_uris:
              - 'https://docs.icytv.de/accounts/openid_connect/authelia/login/callback/'
              - 'https://docs.icytv.de/accounts/openid_connect/authentik/login/callback/'
              - 'https://docs.icytv.de/accounts/authentik/login/callback/'
            scopes:
              - 'openid'
              - 'profile'
              - 'email'
              - 'groups'
            response_types:
              - 'code'
            grant_types:
              - 'authorization_code'
            token_endpoint_auth_method: 'client_secret_basic'

          - client_id: 'W05g2BNpNxhqJuzvcFSEh98KK8NDaTYaYOwhIdQ8'
            client_name: 'Audiobookshelf'
            client_secret: '{audiobookshelf_hash}'
            public: false
            authorization_policy: 'client_policy'
            redirect_uris:
              - 'https://audiobook.icytv.de/auth/openid/callback'
              - 'https://audiobook.icytv.de/auth/openid/mobile-redirect'
              - 'audiobookshelf://oauth'
            scopes:
              - 'openid'
              - 'profile'
              - 'email'
            response_types:
              - 'code'
            grant_types:
              - 'authorization_code'
            token_endpoint_auth_method: 'client_secret_basic'
"""
    (authelia_dir / "configmap.yaml").write_text(authelia_config_yaml)

    # Save credentials securely to XDG-compliant state directory (chmod 0600)
    xdg_state = os.environ.get("XDG_STATE_HOME") or str(pathlib.Path.home() / ".local" / "state")
    creds_dir = pathlib.Path(xdg_state) / "authelia"
    creds_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(creds_dir, 0o700)
    creds_path = creds_dir / "credentials.txt"
    creds_content = f"""LLDAP Admin Credentials:
Username: admin
Password: {lldap_admin_password}

User Credentials:
Username: michael
Email: michael.finger@icytv.de
Password: {user_pwd}

OIDC Client Secrets (Plaintext):
Headlamp: {headlamp_secret}
Paperless: {paperless_secret}
Audiobookshelf: {audiobookshelf_secret}
Paperless Sign Token: {sign_token}
"""
    creds_path.write_text(creds_content)
    os.chmod(creds_path, 0o600)

    print(f"4/5 All secrets encrypted and saved into repository.")
    print(f"5/5 Credentials securely written to {creds_path} (mode 0600).")

if __name__ == "__main__":
    main()
