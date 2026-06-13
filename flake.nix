{
  description = "My dotfiles";

  inputs = {
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    terranix = {
      url = "github:terranix/terranix";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
  };

  outputs = { nixpkgs-stable, nixpkgs-unstable, home-manager, terranix, ... }:
    let
      createConfiguration = { system, username, homeDirectory, dotfilesPath, extraModules, pkgs }: home-manager.lib.homeManagerConfiguration {
        pkgs = import pkgs {
          inherit system;
          config.allowUnfreePredicate = pkg:
            builtins.elem (pkgs.lib.getName pkg) [ "1password-cli" ];
        };

        modules = [
          ./modules/shared.nix
          ./modules/programs/git.nix
          ./modules/programs/slync.nix
        ] ++ extraModules;

        extraSpecialArgs = {
          inherit system username homeDirectory dotfilesPath;
        };
      };
    in
    {
      # Personal Mac
      homeConfigurations."steven@stevens-mbp-14" = createConfiguration rec {
        system = "aarch64-darwin";
        username = "steven";
        homeDirectory = "/Users/${username}";
        dotfilesPath = "${homeDirectory}/.config/home-manager";
        extraModules = [ ./modules/personal.nix ./modules/mac-shared.nix ];
        pkgs = nixpkgs-stable;
      };
      # Gigante NixOS
      homeConfigurations."steven@gigante" = createConfiguration rec {
        system = "x86_64-linux";
        username = "steven";
        homeDirectory = "/home/${username}";
        dotfilesPath = "${homeDirectory}/dotfiles";
        extraModules = [ ./modules/personal.nix ];
        pkgs = nixpkgs-stable;
      };
      # Homelad NixOS LXC - uses unstable to support the Proxmox host's newer NVIDIA kernel driver
      homeConfigurations."steven@homelad" = createConfiguration rec {
        system = "x86_64-linux";
        username = "steven";
        homeDirectory = "/home/${username}";
        dotfilesPath = "${homeDirectory}/dotfiles";
        extraModules = [ ./modules/personal.nix ];
        pkgs = nixpkgs-unstable;
      };

      apps.x86_64-linux.home-manager = {
        type = "app";
        program = "${nixpkgs-stable.legacyPackages.x86_64-linux.home-manager}/bin/home-manager";
      };

      apps.aarch64-darwin =
        let
          system = "aarch64-darwin";
          pkgs = nixpkgs-stable.legacyPackages.${system};

          # Built from source to fix a serialization bug: the provider sends
          # "schedule_with_duration": null on WLAN updates, which UniFi
          # Express 7 firmware rejects with api.err.InvalidPayload (400).
          terraform-provider-unifi = pkgs.buildGoModule rec {
            pname = "terraform-provider-unifi";
            version = "0.41.25";
            src = pkgs.fetchFromGitHub {
              owner = "ubiquiti-community";
              repo = "terraform-provider-unifi";
              rev = "v${version}";
              hash = "sha256-Y3MgMRhWmXYp0aYLIkV2Ug5bZb8LsPYr3oJkXhPtQoo=";
            };
            vendorHash = "sha256-ghS0Jii0o3BBrb23us/H6XLZ5ry52KD5hFelhUqlVnw=";
            # Patch the vendored go-unifi SDK to omit the field when empty
            modPostBuild = ''
              sed -i 's/json:"schedule_with_duration"/json:"schedule_with_duration,omitempty"/' \
                vendor/github.com/ubiquiti-community/go-unifi/unifi/wlan.generated.go
            '';
            # The provider accepts src_mac in config but never sends it to the
            # API, turning a per-device rule into a drop-everything rule.
            patches = [ ./unifi/patches/firewall-rule-src-mac.patch ];
            # The provider validates rule_index against the pre-9.x controller
            # ranges; newer firmware (Express 7) assigns/expects 2xxxx indexes.
            postPatch = ''
              sed -i 's/int64validator.Between(2000, 2999)/int64validator.Between(2000, 29999)/' \
                unifi/firewall_rule_resource.go
            '';
            doCheck = false;
            subPackages = [ "." ];
          };

          terraformConfig = terranix.lib.terranixConfiguration {
            inherit system;
            modules = [ ./unifi/config.nix ];
          };

          unifiTofu = name: command: pkgs.writeShellScript "unifi-${name}" ''
            set -e
            if [ ! -d "unifi" ]; then
              echo "Error: unifi/ directory not found. Run from repository root." >&2
              exit 1
            fi

            UNIFI_API_KEY=$(cat "$HOME/.config/unifi/api_key")
            export UNIFI_API_KEY
            export UNIFI_API="https://192.168.1.1"
            export UNIFI_INSECURE="true"
            TF_VAR_wifi_passphrase=$(cat "$HOME/.config/unifi/wifi_passphrase")
            export TF_VAR_wifi_passphrase
            export TF_VAR_unifi_api_key="$UNIFI_API_KEY"
            # Use our patched provider build (see terraform-provider-unifi above)
            export TF_CLI_CONFIG_FILE=${pkgs.writeText "unifi-tofu.tfrc" ''
              provider_installation {
                dev_overrides {
                  "ubiquiti-community/unifi" = "${terraform-provider-unifi}/bin"
                }
                direct {}
              }
            ''}

            rm -f unifi/config.tf.json
            cp ${terraformConfig} unifi/config.tf.json
            cd unifi
            if [ ! -d .terraform ]; then
              ${pkgs.opentofu}/bin/tofu init
            fi
            ${pkgs.opentofu}/bin/tofu ${command}
          '';
        in
        {
          home-manager = {
            type = "app";
            program = "${pkgs.home-manager}/bin/home-manager";
          };
          unifi-plan = {
            type = "app";
            program = toString (unifiTofu "plan" "plan");
          };
          unifi-apply = {
            type = "app";
            program = toString (unifiTofu "apply" "apply -auto-approve");
          };
        };
    };
}
