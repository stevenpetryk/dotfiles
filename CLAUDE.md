# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NixOS + Home Manager dotfiles repository. Home Manager uses Nix Flakes; NixOS configurations are standalone.

## Build Commands

```bash
# Switch home-manager configuration (primary command)
./bin/hms

# Or directly:
nix run .#home-manager -- switch --flake .

# Rebuild NixOS system (after initial bootstrap with -I)
sudo nixos-rebuild switch
```

## Architecture

### Flake Structure

The `flake.nix` defines:

- **Inputs**: `nixpkgs-stable` (25.11), `nixpkgs-unstable`, `home-manager` (release-25.11)
- **Home Manager configs**: `steven@stevens-mbp-14` (macOS), `steven@gigante` (Linux desktop), `steven@gpulad` (NixOS GPU VM)

NixOS configurations in `nixos/` are standalone (not flake-based) and configure their own channels.

### Module Organization

```
modules/                    # Home Manager modules (user-level)
├── shared.nix              # Core CLI tools for all machines (zsh, fzf, atuin, neovim, etc.)
├── personal.nix            # Development tools for Linux (Node.js, Rust, Python)
├── mac-shared.nix          # macOS-specific utilities
└── programs/
    ├── git.nix             # Git + delta + gh configuration
    └── slync.nix           # Watchman-based file sync tool

nixos/                      # NixOS system configurations (personal machines only)
├── gigante/                # Desktop/gaming machine (KDE Plasma 6, NVIDIA, Steam)
└── modules/                # Shared NixOS modules (empty, for future use)
```

gpulad's system config is NOT here — it lives in the lads-inc monorepo
(`nixos/hosts/gpulad/`, flake output `nixosConfigurations.gpulad`), applied
with `sudo nixos-rebuild switch --flake /srv/keen-mind#gpulad --impure`. This
repo only carries steven's home-manager config for that host.

### Configuration Inheritance

Each home-manager config composes modules:

- macOS: `shared.nix` + `mac-shared.nix` + `git.nix`
- gigante: `shared.nix` + `personal.nix` + `git.nix` + `slync.nix`
- gpulad: `shared.nix` + `personal.nix` + `git.nix` + `slync.nix`

### Key Patterns

- `extraSpecialArgs` passes machine-specific config (e.g., `isLinux`, `pkgs-unstable`) to modules
- `writeShellApplication` / `writeScriptBin` generates CLI tools declaratively
- Cachix binary caches (`cuda-maintainers`, `nix-community`) for faster rebuilds

### Machine-Specific Notes

- **gigante**: Primary workstation with KDE Plasma 6, proprietary NVIDIA driver, gaming setup (Steam, Lutris, Sunshine streaming)
- **gpulad**: home-manager only here (see above for where its system config lives)
