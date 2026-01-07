{ pkgs, ... }:

{
  home.packages = with pkgs; [
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
