{lib, ...}: {
  variable = {
    cloudflare_api_token.sensitive = true;
    tailscale_trust_credential.sensitive = true;
  };

  provider.cloudflare.api_token = lib.tf.ref "var.cloudflare_api_token";

  resource.cloudflare_zero_trust_tunnel_cloudflared."server-tunnel" = {
    name = "server-tunnel";
  };
}
