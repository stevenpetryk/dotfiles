{ config, pkgs, ... }:

{
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
