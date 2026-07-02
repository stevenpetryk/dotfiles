{ config, pkgs, lib, ... }:

# Clad egress + browser containment. Imported from configuration.nix.
#
# Two independent controls:
#
#   A. Browser isolation (ALWAYS ON). Playwright/chromium runs as the dedicated
#      `clad-browser` user, whose nftables rule allows LOOPBACK ONLY — strictly
#      localhost, no internet. Pairs with the harness (clad), which launches the
#      browser as this user via a scoped runuser. Playwright's --allowed-origins
#      is explicitly NOT a security boundary (upstream), so the boundary is here.
#
#   B. General egress — `egressMode`, one of:
#        "open"    — no restriction; clad has direct internet (original posture).
#        "observe" — redirect clad's outbound TLS through the local SNI proxy,
#                    which LOGS every SNI then PASSES THROUGH to the real host
#                    (allow-all, non-disruptive). Use this to learn exactly which
#                    hosts clad talks to before locking down. nftables also logs
#                    clad's non-443 / non-loopback egress by IP, so HTTP/3 (UDP
#                    443), plain HTTP, and odd ports aren't a blind spot. The SNI
#                    log feeds the `allow` list below.
#        "lock"    — drop clad's direct egress; only the `allow` SNI list passes,
#                    everything else proxies to a dead end (refused).
#      `observe`/`lock` use the SAME transparent SNI proxy (nginx stream +
#      ssl_preread), so observing through it proves the path works for clad's
#      real traffic before enforcement depends on it.
#
# Blast radius is narrow: every rule is skuid-scoped to clad / clad-browser /
# nginx. Other services (keen-mind, vtt, cloudflared, tailscale) are untouched
# (default policy stays accept).

let
  # Master switch for control B. Move open → observe → (tune allow) → lock.
  egressMode = "lock"; # "open" | "observe" | "lock"

  lockEgress = egressMode == "lock";
  observe = egressMode == "observe";
  redirectClad = lockEgress || observe; # both route clad's :443 to the proxy

  # The host's upstream resolvers. systemd-resolved is NOT enabled here, so the
  # 127.0.0.53 stub doesn't answer — point nginx at the real nameservers (matches
  # /etc/resolv.conf): the LAN router for normal internet hosts, plus
  # Tailscale's quad-100 MagicDNS resolver for *.ts.net names (e.g. clad
  # reaching gitlab-proto.tail324fea.ts.net) now that accept-dns is on host-wide.
  resolver = "192.168.1.1 100.100.100.100";

  # Allowlist for `lock` (matched against the TLS SNI). Build this from the
  # `observe`-mode SNI log before flipping to lock. Keep tight — it's the egress
  # boundary. Each entry is also a small exfil surface.
  allow = {
    "api.anthropic.com" = "api.anthropic.com:443"; # Claude SDK / CLI
    "mcp-proxy.anthropic.com" = "mcp-proxy.anthropic.com:443"; # claude.ai MCP integrations (Gmail/Calendar/Drive/Monarch/…)
    "statsig.anthropic.com" = "statsig.anthropic.com:443"; # CLI telemetry; drop if you'd rather
    "downloads.claude.ai" = "downloads.claude.ai:443"; # Claude CLI asset/update downloads
    "platform.claude.com" = "platform.claude.com:443"; # Claude platform
    "github.com" = "github.com:443"; # GitHub API/HTTPS (git-SSH is deliberately cut — clad's git is GitLab over the tailnet)
    "api.github.com" = "api.github.com:443";
    "codeload.github.com" = "codeload.github.com:443";
    "objects.githubusercontent.com" = "objects.githubusercontent.com:443";
    "cache.nixos.org" = "cache.nixos.org:443"; # nix substituter
    "releases.nixos.org" = "releases.nixos.org:443"; # nix channels / eval
    "channels.nixos.org" = "channels.nixos.org:443"; # nix channels / eval
    "registry.npmjs.org" = "registry.npmjs.org:443"; # bun / npm deps
    "oauth2.googleapis.com" = "oauth2.googleapis.com:443"; # GCP SA token exchange (clad's Vertex SA)
  };
  # Destinations that bypass the SNI proxy entirely and go out directly.
  # Tailscale peer IPs don't reliably hit the `nat_out` redirect below — its
  # own policy routing for the 100.64.0.0/10 CGNAT range appears to win before
  # our nat hook does — so proxying tailnet traffic through nginx just hangs.
  # Narrow, single-IP carve-out rather than exempting the whole tailnet range.
  tailnetDirect = {
    "gitlab-proto" = "100.91.188.72"; # gitlab-proto.tail324fea.ts.net — CI/glab for clad
  };
  nginxPort = 8443; # clad's redirected 443 lands here
  deadEnd = "127.0.0.1:1"; # non-allowlisted / no-SNI proxies here → refused
  sniLog = "/var/log/nginx/clad-egress-sni.log"; # observe/lock SNI access log
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

  # ── nftables: browser loopback-only (always); clad redirect/log/drop (mode) ──
  # NOTE: enabling the nftables backend replaces the iptables-nft firewall. It IS
  # a backend switch — verify host firewall rules (tailscale ports) still apply
  # after rebuild.
  networking.nftables.enable = true;
  # skuid rules reference users by NAME; the build-time `nft -c` check runs in a
  # sandbox where clad-browser/clad don't exist in /etc/passwd, so it can't
  # resolve them. Skip that check — the live system resolves the names fine, and
  # nftables.service activation still fails loudly on a genuinely bad ruleset.
  networking.nftables.checkRuleset = false;
  networking.nftables.tables.clad-egress = {
    family = "inet";
    content = ''
      ${lib.optionalString redirectClad ''
      # Redirect clad's outbound TLS into the local SNI proxy. After this the dst
      # is loopback, so the loopback-accepts below cover it.
      chain nat_out {
        type nat hook output priority -100; policy accept;
        ${lib.concatStringsSep "\n        "
          (lib.mapAttrsToList (name: ip: ''meta skuid "clad" ip daddr ${ip} return # ${name}: direct, no SNI proxy'') tailnetDirect)}
        meta skuid "clad" tcp dport 443 redirect to :${toString nginxPort}
      }
      ''}

      chain filter_out {
        type filter hook output priority 0; policy accept;

        # Allow loopback (lets clad-browser reach keen-mind-web; lets clad reach
        # the SNI proxy — its redirected :443 is now loopback-destined).
        oifname "lo" accept
        ip  daddr 127.0.0.0/8 accept
        ip6 daddr ::1 accept

        # A. Browser → loopback only. Everything else dropped (strictly localhost).
        meta skuid "clad-browser" drop

        # tailnetDirect: accepted here so `lock` mode's drop-all-else below
        # doesn't catch these — they never go through the SNI proxy/allowlist.
        ${lib.concatStringsSep "\n        "
          (lib.mapAttrsToList (name: ip: ''meta skuid "clad" ip daddr ${ip} accept # ${name}'') tailnetDirect)}

        ${lib.optionalString observe ''
        # B/observe: log clad's egress that ISN'T the redirected-to-loopback :443
        # (nginx already captures those as SNI). Catches HTTP/3 (UDP 443), plain
        # HTTP, and any non-443 port — by IP. Non-blocking (policy stays accept).
        meta skuid "clad" ip  daddr != 127.0.0.0/8 log prefix "clad-egress-other: " level info
        meta skuid "clad" ip6 daddr != ::1         log prefix "clad-egress-other6: " level info
        ''}

        ${lib.optionalString lockEgress ''
        # DNS carve-out: clad's ONLY resolver is Tailscale MagicDNS
        # (100.100.100.100, per resolv.conf — systemd-resolved is off, no
        # loopback stub). Without this the drop below kills all name resolution,
        # so clad reaches nothing — even the proxied :443 hosts, since it still
        # resolves the name to an IP before the nat redirect fires. MagicDNS
        # forwards public names upstream, so this one resolver covers tailnet +
        # internet alike.
        meta skuid "clad" ip daddr 100.100.100.100 udp dport 53 accept
        meta skuid "clad" ip daddr 100.100.100.100 tcp dport 53 accept

        # B/lock: any external destination from clad (other than the redirected
        # :443 accepted above) is dropped — no direct egress. This deliberately
        # includes git-SSH to github.com:22 (SSH has no TLS SNI, so it can't ride
        # the proxy) — clad's git is keen-mind on GitLab, reached direct over the
        # tailnet (tailnetDirect above), so GitHub egress is not needed.
        meta skuid "clad" drop
        ''}
      }
    '';
  };

  # ── B. Transparent SNI proxy (observe = allow-all + log; lock = allowlist) ──
  # ssl_preread reads the ClientHello SNI, then relays raw TLS bytes onward to
  # the chosen host — clad's end-to-end TLS is untouched. Every connection is
  # logged with its SNI to ${sniLog}.
  services.nginx = lib.mkIf redirectClad {
    enable = true;
    streamConfig = ''
      # ipv6=off: this host has no IPv6 route, so passthrough to an AAAA upstream
      # fails "Network is unreachable". Force A records only.
      resolver ${resolver} valid=30s ipv6=off;

      log_format clad_sni '$time_iso8601 sni="$ssl_preread_server_name" '
                          'upstream="$clad_upstream" status=$status '
                          'sent=$bytes_sent recv=$bytes_received '
                          'dur=$session_time';

      map $ssl_preread_server_name $clad_upstream {
        ${lib.optionalString observe ''
        # observe: pass through to whatever host the SNI names (allow-all). A
        # connection with no SNI can't be forwarded blind → dead end (logged).
        ""        ${deadEnd};
        default   $ssl_preread_server_name:443;
        ''}
        ${lib.optionalString lockEgress ''
        # lock: only the allowlist (+ dynamic-subdomain hosts) passes; else dead end.
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
        # Vertex AI — global + regional endpoints (us-central1-aiplatform, …).
        # Deliberately aiplatform only, NOT all of googleapis.com: the SA is
        # Vertex-scoped and the egress boundary should match.
        ~^([a-z0-9-]+-)?aiplatform\.googleapis\.com$  $ssl_preread_server_name:443;
        ''}
      }

      server {
        listen 127.0.0.1:${toString nginxPort};
        ssl_preread on;
        proxy_pass $clad_upstream;
        proxy_connect_timeout 10s;
        # Don't sever long-lived idle connections (Discord gateway wss heartbeats
        # ~every 41s keep it active, but be generous).
        proxy_timeout 1h;
        access_log ${sniLog} clad_sni;
      }
    '';
  };

  # ── VALIDATION ────────────────────────────────────────────────────────────
  # Browser isolation (active in every mode), after `nixos-rebuild switch`:
  #   sudo -u clad-browser curl -sS https://github.com/   → blocked
  #   sudo -u clad-browser curl -sS http://127.0.0.1:PORT/ → works
  #
  # observe mode (active now): after rebuild, clad keeps working AND every host
  # it dials is recorded. Harvest the hostname list for the `allow` map with:
  #   awk -F'sni="' '{print $2}' ${sniLog} | cut -d'"' -f1 | sort | uniq -c | sort -rn
  #   journalctl -k | grep clad-egress-other   # non-443 egress (by IP)
  # Watch journalctl -u clad for clean Discord gateway reconnects through the proxy.
  #
  # Before flipping egressMode = "lock", additionally:
  #   sudo -u clad curl -sS https://example.com/  → blocked (not in allow)
  #   confirm the tuned `allow` covers everything observe surfaced (registries, etc.)
  # Fallback if the relay misbehaves: set egressMode = "open" and rebuild.
}
