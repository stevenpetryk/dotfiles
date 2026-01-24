{ config, pkgs, lib, ... }:

{
  # Cloudflare Tunnel for lads.games (remotely managed via Terraform)
  systemd.services.cloudflared-tunnel = {
    description = "Cloudflare Tunnel for lads.games";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    script = ''
      ${pkgs.cloudflared}/bin/cloudflared tunnel run --token $(cat /var/secrets/cloudflared-tunnel-token)
    '';

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5";
    };
  };

  # Nginx for lads.games
  services.nginx = {
    enable = true;
    virtualHosts."lads.games" = {
      locations."/" = {
        root = pkgs.writeTextDir "index.html" ''
          <!DOCTYPE html>
          <html>
            <head><title>Keen Mind</title></head>
            <body><h1>Hello Keen Mind!</h1></body>
          </html>
        '';
        tryFiles = "/index.html =404";
      };
    };
  };

  # Cockpit for system administration
  # Note: Cockpit doesn't support header-based auto-auth well.
  # It's protected by Cloudflare Access, but you'll still need to log in with system credentials.
  services.cockpit = {
    enable = true;
    port = 9090;
    settings = {
      WebService = {
        Origins = lib.mkForce "https://cockpit.lads.games";
        ProtocolHeader = "X-Forwarded-Proto";
      };
    };
  };

  # Grafana for monitoring
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3001;
        root_url = "https://grafana.lads.games";
      };
      "auth.proxy" = {
        enabled = true;
        header_name = "Cf-Access-Authenticated-User-Email";
        header_property = "email";
        auto_sign_up = true;
      };
      auth = {
        disable_login_form = true;
      };
      users = {
        auto_assign_org = true;
        auto_assign_org_role = "Admin";
      };
    };
  };

  # Keen Mind Discord Bot
  systemd.services.keen-mind = {
    description = "Keen Mind Discord Bot";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = "/home/steven";
      # Required for nix-build in agent.ts which uses <nixpkgs>
      NIX_PATH = "nixpkgs=${pkgs.path}";
    };

    serviceConfig = {
      Type = "simple";
      User = "steven";

      WorkingDirectory = "/home/steven/src/keen-mind";

      ReadOnlyPaths = [
        "/home/steven/src/keen-mind"
        "/nix/store"
      ];
      ReadWritePaths = [
        "/home/steven/keen-mind-data"
        "/tmp"
      ];

      ExecStart = "${pkgs.nix}/bin/nix develop /home/steven/src/keen-mind --command bun run cli bot";
      Restart = "always";
      RestartSec = "10";
    };
  };
}
