{ config, pkgs, ... }:

{
  # Keen Mind Discord Bot
  systemd.services.keen-mind = {
    description = "Keen Mind Discord Bot";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      NIX_PATH = "nixpkgs=${pkgs.path}";
      HOME = "/home/steven";
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

      ExecStart = "${pkgs.nix}/bin/nix-shell /home/steven/src/keen-mind/shell.nix --command \"corepack pnpm run -s cli bot\"";
      Restart = "always";
      RestartSec = "10";
    };
  };
}
