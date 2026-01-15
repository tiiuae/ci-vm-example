{ inputs, ... }:
{
  imports = [
    inputs.devshell.flakeModule
  ];
  perSystem =
    { pkgs, ... }:
    {
      devshells = {
        default = {
          devshell = {
            packages = with pkgs; [
              git
              nix
              nixos-rebuild
              python3
              python3.pkgs.aiohttp
              python3.pkgs.deploykit
              python3.pkgs.invoke
              python3.pkgs.loguru
              python3.pkgs.pycodestyle
              python3.pkgs.pylint
              python3.pkgs.tabulate
              reuse
              sops
              ssh-to-age
            ];
          };
          commands = [
            {
              help = "Update all sops yaml and json files according to .sops.yaml rules";
              name = "update-sops-files";
              command = "set -x; find . -type f -iname 'secrets.yaml' -exec sops updatekeys --yes {} ';'";
              category = "scripts";
            }
            {
              help = "Update Jenkins plugins";
              name = "update-jenkins-plugins";
              command = ''
                FLAKE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
                if [ -z "$FLAKE_ROOT" ]; then
                  echo "WARNING: flake root not round; skipping helpers installation."
                  return
                fi
                update-jenkins-plugins () {
                  conf_path="$1"
                  if [ -z "$conf_path" ]; then
                    echo "Error: missing first argument - expecting relative path to host configuration"
                    return
                  fi
                  python3 "$FLAKE_ROOT"/scripts/resolve_plugins.py \
                    --jenkins-version ${pkgs.jenkins.version} \
                    --plugins-file "$FLAKE_ROOT"/"$conf_path"/plugins.txt \
                    --output "$FLAKE_ROOT"/"$conf_path"/plugins.json
                }
                update-jenkins-plugins "$FLAKE_ROOT"/hosts/jenkins-controller
              '';
              category = "scripts";
            }
          ];
        };
      };
    };
}
