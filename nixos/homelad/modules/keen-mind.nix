{ config, pkgs, ... }:

{
  # Create keen_mind system user and group
  users.users.keen_mind = {
    isSystemUser = true;
    group = "keen_mind";
    extraGroups = [ "keen-mind-readers" ];
  };

  users.groups.keen_mind = {};
  users.groups.keen-mind-readers = {};

  # Enable PostgreSQL
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
    ensureDatabases = [ "keen_mind" ];
    ensureUsers = [
      {
        name = "keen_mind";
        ensureDBOwnership = true;
      }
    ];
    authentication = pkgs.lib.mkOverride 10 ''
      #type database  DBuser  auth-method
      local all       all     trust
      host  all       all     127.0.0.1/32   trust
      host  all       all     ::1/128        trust
    '';
  };
  # Keen Mind Discord Bot
  systemd.services.keen-mind = {
    description = "Keen Mind Discord Bot";
    after = [ "network.target" "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [ nodejs_24 python312 pnpm ];

    environment = {
      KEEN_MIND_DATA_DIR = "/var/lib/keen-mind/recordings";
      KEEN_MIND_CACHE_DIR = "/var/cache/keen-mind";
      KEEN_MIND_RUNTIME_DIR = "/run/keen-mind";
      DATABASE_URL = "postgresql://keen_mind@localhost/keen_mind";
    };

    serviceConfig = {
      Type = "simple";
      User = "keen_mind";
      Group = "keen_mind";

      WorkingDirectory = "/srv/keen-mind/recorder_bot";

      # Create FHS dirs with correct perms
      StateDirectory = "keen-mind/recordings";
      CacheDirectory = "keen-mind";
      LogsDirectory = "keen-mind";
      RuntimeDirectory = "keen-mind";
      StateDirectoryMode = "0700";

      # Sandboxing: keep /home hidden; OS read-only
      ProtectHome = "yes";
      ProtectSystem = "strict";

      # Allow read of the repo; allow writes only to these dirs
      ReadOnlyPaths = [ "/srv/keen-mind" ];
      ReadWritePaths = [
        "/var/lib/keen-mind"
        "/var/cache/keen-mind"
        "/var/log/keen-mind"
        "/run/keen-mind"
      ];
      UMask = "0077";

      ExecStart = "${pkgs.nodejs_24}/bin/node --experimental-strip-types --env-file=../.env ./src/index.ts";
      Restart = "always";
      RestartSec = "10";
    };
  };
}