{ config, pkgs, lib, ... }:

# Clad egress + browser containment. Imported from configuration.nix.
#
# Two independent controls, gated separately:
#
#   A. Browser isolation (ALWAYS ON). Playwright/chromium runs as the dedicated
#      `clad-browser` user, whose nftables rule allows LOOPBACK ONLY — strictly
#      localhost, no internet. Pairs with the harness (clad), which launches the
#      browser as this user via a scoped runuser. Playwright's --allowed-origins
#      is explicitly NOT a security boundary (upstream), so the boundary is here.
#
#   B. General egress allowlist (OFF — `lockEgress = false`). When enabled, all of
#      clad's own outbound is dropped except an allowlist of hostnames, enforced
#      by a transparent SNI proxy (nginx stream + ssl_preread). Currently INERT:
#      steven isn't ready to restrict clad's general internet (the allowlist would
#      first need tuning for clad's dev work — npm/PyPI/etc. fetches). The code is
#      kept here so flipping `lockEgress = true` + rebuild turns it on; see the
#      VALIDATION notes at the bottom before doing so.
#
# Blast radius is narrow: every rule is skuid-scoped to clad / clad-browser /
# nginx. Other services (keen-mind, vtt, cloudflared, tailscale) are untouched
# (default policy stays accept).

let
  # Master switch for control B (clad's general egress lockdown). Leave false
  # until the allowlist below is tuned for what clad's dev work actually fetches.
  lockEgress = false;

  # Allowlist for control B (matched against the TLS SNI). Only consulted when
  # lockEgress = true. Keep tight — it's the egress boundary. Widen for any
  # package registries clad needs (each is also a small exfil surface).
  allow = {
    "api.anthropic.com" = "api.anthropic.com:443";              # Claude SDK / CLI
    "statsig.anthropic.com" = "statsig.anthropic.com:443";      # CLI telemetry; drop if you'd rather
    "github.com" = "github.com:443";
    "api.github.com" = "api.github.com:443";
    "codeload.github.com" = "codeload.github.com:443";
    "objects.githubusercontent.com" = "objects.githubusercontent.com:443";
    "cache.nixos.org" = "cache.nixos.org:443";                  # nix substituter
  };
  nginxPort = 8443;     # clad's redirected 443 lands here (control B)
  deadEnd = "127.0.0.1:1"; # non-allowlisted SNI proxies here → refused
in
{
  # ── A. clad-browser: the loopback-only identity chromium runs as (ALWAYS ON) ──
  users.users.clad-browser = {
    isSystemUser = true;
    group = "clad-browser";
    description = "Clad's Playwright/chromium — loopback-only egress";
    home = "/var/lib/clad-browser";
    createHome = true;
  };
  users.groups.clad-browser = { };
  # clad spawns the Playwright MCP as clad-browser. Scoped NOPASSWD launcher.
  security.sudo.extraRules = [{
    users = [ "clad" ];
    commands = [{
      command = "/run/current-system/sw/bin/runuser -u clad-browser *";
      options = [ "NOPASSWD" "SETENV" ];
    }];
  }];

  # ── nftables: browser loopback-only (always); clad egress drop (only if locked) ──
  # NOTE: enabling the nftables backend replaces the iptables-nft firewall. Low
  # risk here (the only host firewall rule is a tailscale port), but it IS a
  # backend switch — verify the tailscale 2022 rule still applies after rebuild.
  networking.nftables.enable = true;
  networking.nftables.tables.clad-egress = {
    family = "inet";
    content = ''
      ${lib.optionalString lockEgress ''
      # Control B: redirect clad's outbound TLS into the local SNI allowlist.
      # After this the dst is loopback, so the loopback-accepts below cover it.
      chain nat_out {
        type nat hook output priority -100; policy accept;
        meta skuid "clad" tcp dport 443 redirect to :${toString nginxPort}
      }
      ''}

      chain filter_out {
        type filter hook output priority 0; policy accept;

        # Allow loopback (lets clad-browser reach keen-mind-web; under control B
        # also lets clad reach the SNI proxy + the resolved DNS stub).
        oifname "lo" accept
        ip  daddr 127.0.0.0/8 accept
        ip6 daddr ::1 accept

        # A. Browser → loopback only. Everything else dropped (strictly localhost).
        meta skuid "clad-browser" drop

        ${lib.optionalString lockEgress ''
        # B. clad → only the redirected-to-loopback 443 (accepted above); any
        # other external destination from clad is dropped (no direct egress).
        meta skuid "clad" drop
        ''}
      }
    '';
  };

  # ── B. Transparent SNI allowlist (only when lockEgress = true) ─────────────
  # ssl_preread reads the ClientHello SNI, then relays raw TLS bytes onward to
  # the named host — clad's end-to-end TLS is untouched.
  services.nginx = lib.mkIf lockEgress {
    enable = true;
    streamConfig = ''
      resolver 127.0.0.53 valid=30s;   # systemd-resolved stub (loopback)

      map $ssl_preread_server_name $clad_upstream {
        default            ${deadEnd};
        ${lib.concatStringsSep "\n        "
          (lib.mapAttrsToList (h: up: "${h}  ${up};") allow)}
        # Discord (gateway/REST/CDN) — match the apex + any subdomain.
        ~^([a-z0-9-]+\.)?discord\.com$       $ssl_preread_server_name:443;
        ~^([a-z0-9-]+\.)?discord\.gg$        $ssl_preread_server_name:443;
        ~^([a-z0-9-]+\.)?discordapp\.com$    $ssl_preread_server_name:443;
        ~^([a-z0-9-]+\.)?discordapp\.net$    $ssl_preread_server_name:443;
        # githubusercontent buckets rotate subdomains.
        ~^([a-z0-9-]+\.)?githubusercontent\.com$  $ssl_preread_server_name:443;
      }

      server {
        listen 127.0.0.1:${toString nginxPort};
        ssl_preread on;
        proxy_pass $clad_upstream;
        proxy_connect_timeout 10s;
      }
    '';
  };

  # ── VALIDATION ────────────────────────────────────────────────────────────
  # Browser isolation (active now), after `nixos-rebuild switch`:
  #   sudo -u clad-browser curl -sS https://github.com/   → blocked
  #   sudo -u clad-browser curl -sS http://127.0.0.1:PORT/ → works
  #   journalctl -u clad — browser-verify (Playwright) still functions
  #   tailscale status still up; port 2022 rule intact (nftables backend switch)
  #
  # Before flipping `lockEgress = true` (control B), additionally:
  #   sudo -u clad curl -sS https://api.anthropic.com/  → connects (401/ok)
  #   sudo -u clad curl -sS https://example.com/         → blocked
  #   journalctl -u clad — Discord gateway reconnects cleanly through the relay
  #     (the wss relay is the riskiest bit; watch for reconnect loops)
  #   confirm clad's dev work (tests/builds) doesn't need a registry not in `allow`
  # Fallback if the relay misbehaves: an explicit HTTPS_PROXY/ProxyAgent in the
  # harness instead of the transparent redirect.
}
