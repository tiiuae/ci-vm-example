{
  self,
  ...
}:
{
  imports = with self.nixosModules; [
    hosts-common
    user-hrosten
    user-vm-builder
  ];
  networking = {
    hostName = "builder";
  };
}
