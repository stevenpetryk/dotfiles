{ pkgs, ... }:

{
  home.packages = with pkgs; [
    _1password-cli
    eternal-terminal  # `et` client — auto-reconnecting remote shell (see homelad etserver)
    pkg-config

    (pkgs.writeScriptBin "ql" ''
      nohup qlmanage -p $1 >/dev/null 2>&1 &
    '')
  ];

  home.shellAliases = {
    # Reveal in Finder
    reveal = "open -R";
  };
}
