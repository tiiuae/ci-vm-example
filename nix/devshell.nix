{
  perSystem =
    { pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        shellHook = ''
          FLAKE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
          if [ -z "$FLAKE_ROOT" ]; then
            echo "WARNING: flake root not round; skipping helpers installation."
            return
          fi
          update-sops-files () {
            find . -type f -iname 'secrets.yaml' -exec sops updatekeys --yes {} ';'
          }
          update-jenkins-plugins () {
            conf_path=hosts/jenkins-controller
            if [ -z "$conf_path" ]; then
              echo "Error: missing first argument - expecting relative path to host configuration"
              return
            fi
            python3 "$FLAKE_ROOT"/scripts/resolve_plugins.py \
              --jenkins-version ${pkgs.jenkins.version} \
              --plugins-file "$FLAKE_ROOT"/"$conf_path"/plugins.txt \
              --output "$FLAKE_ROOT"/"$conf_path"/plugins.json
          }
          echo ""
          echo 1>&2 "Welcome to the development shell!"
          echo ""
          echo "This shell provides following helper commands:"
          echo " - update-sops-files"
          echo " - update-jenkins-plugins"
          echo ""
        '';
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
    };
}
