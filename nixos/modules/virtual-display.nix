# Yoinked from https://github.com/DaRacci/nix-config/blob/cb890cc6aac262079bfa3dc4360014145255aa1d/modules/nixos/hardware/display.nix#L17
# Thank you, DaRacci! <3
{ config
, pkgs
, lib
, ...
}:
let
  cfg = config.hardware.display.virtual;
in
{
  options.hardware.display.virtual = {
    enable = lib.mkEnableOption "Enable Virtual Display Support";

    # TODO :: Validate that the resolution & refreshRate are available in the EDID using the edid-decode tool
    edidBinary = lib.mkOption {
      type = lib.types.path;
      description = ''
        The binary file containing the EDID data for the virtual display.
        This file can be generated using a tool like AW EDID Editor that can be ran under Wine.
      '';
    };

    # TODO :: Validate that its formatted correctly
    resolution = lib.mkOption {
      type = lib.types.str;
      example = "1920x1080";
      description = "Resolution of the virtual display";
    };

    refreshRate = lib.mkOption {
      type = lib.types.int;
      example = 60;
      description = "Refresh rate of the virtual display";
    };

    connector = lib.mkOption {
      type = lib.types.str;
      example = "HDMI-A-1";
      description = ''
        The connector to use for the virtual display.

        This must be a valid connector for your hardware.
        You can find the available connectors by running `for p in /sys/class/drm/*/status; do con=''${p%/status}; echo -n "''${con#*/card?-}: "; cat $p; done`
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.display = {
      outputs.${cfg.connector} = {
        mode = "${cfg.resolution}@${toString cfg.refreshRate}e";
        edid = "virtual.bin";
      };

      edid = {
        enable = true;
        packages = [
          (pkgs.runCommand "edid-virtual" { } ''
            mkdir -p "$out/lib/firmware/edid"
            cat ${cfg.edidBinary} > "$out/lib/firmware/edid/virtual.bin"
          '')
        ];
      };
    };

    boot.kernelParams = [
      "drm.edid_firmware=HDMI-A-1:edid/virtual.bin"
      "video=HDMI-A-1:e"
    ];
  };
}
