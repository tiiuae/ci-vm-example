{ inputs, ... }:
{
  imports = with inputs; [
    flake-root.flakeModule
    treefmt-nix.flakeModule
  ];
  perSystem =
    { config, pkgs, ... }:
    {
      treefmt.config = {
        package = pkgs.treefmt;
        inherit (config.flake-root) projectRootFile;
        programs = {
          nixfmt = {
            enable = true;
            package = pkgs.nixfmt;
            excludes = [ "**/plugins.nix" ]; # file is automatically generated
          };
          deadnix.enable = true;
          statix.enable = true;
          shellcheck.enable = true;
        };
      };
      formatter = config.treefmt.build.wrapper;
    };
}
