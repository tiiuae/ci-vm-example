{
  vcpus ? 2,
  ram_gb ? 4,
  disk_gb ? 16,
  ...
}:
{
  fileSystems."/".device = "/dev/disk/by-label/nixos";
  boot.loader.grub.device = "/dev/disk/by-label/nixos";
  virtualisation.vmVariant.virtualisation.graphics = false;
  virtualisation.vmVariant.virtualisation.cores = vcpus;
  virtualisation.vmVariant.virtualisation.memorySize = ram_gb * 1024;
  virtualisation.vmVariant.virtualisation.diskSize = disk_gb * 1024;
  virtualisation.vmVariant.virtualisation.writableStore = true;
  virtualisation.vmVariant.virtualisation.useNixStoreImage = true;
  virtualisation.vmVariant.virtualisation.mountHostNixStore = false;
  virtualisation.vmVariant.virtualisation.writableStoreUseTmpfs = false;
  virtualisation.vmVariant.virtualisation.qemu.options = [
    "-device virtio-balloon"
    "-enable-kvm"
  ];
  virtualisation.vmVariant.zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
  };
}
