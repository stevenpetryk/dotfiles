{ pkgs, system, ... }:

let
  unstable = import
    (fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/5148520bfab61f99fd25fb9ff7bfbb50dad3c9db.tar.gz";
      sha256 = "sha256:1dfjmz65h8z4lk845724vypzmf3dbgsdndjpj8ydlhx6c7rpcq3p";
    })
    { localSystem = system; };
in
(unstable.rustPlatform.buildRustPackage
rec {
  pname = "ast-grep";
  version = "0.12.2";

  src = unstable.fetchFromGitHub {
    owner = "ast-grep";
    repo = "ast-grep";
    rev = version;
    hash = "sha256-N9hfHgzqwV/G3/xNY2Vx1i2dW6BcABJ/4lkhnLuvIns=";
  };

  cargoHash = "sha256-3ntsPC6OWtSN3MH+3wN2BgOqH69jiW93/xfLY+niARI=";

  # error: linker `aarch64-linux-gnu-gcc` not found
  postPatch = ''
    rm .cargo/config.toml
  '';

  # Disable tests because this isn't nixpkgs lol
  doCheck = false;
})
