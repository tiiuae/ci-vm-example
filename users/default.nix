{
  flake.nixosModules = {
    user-hrosten = import ./hrosten.nix;
    user-vm-builder = import ./vm-builder.nix;
  };
}
