# ci-vm-example

Proof-of-concept to trial the following:
- Using flake app targets to run nixos configurations as [qemu-vm.nix](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/qemu-vm.nix) virtual machines (VMs)
- Using [sops-nix](https://github.com/Mic92/sops-nix) to automatically deploy secrets on the running VMs
- Spin-up a complete ephemeral build environment using qemu VMs over an existing infra

## Requirements
- Nix package manager: https://nixos.org/download/
- [KVM](https://en.wikipedia.org/wiki/Kernel-based_Virtual_Machine) enabled on the host

## Quick Start
```
❯ nix run github:tiiuae/ci-vm-example#run-vm-jenkins-controller-ephemeral
```

Alternatively, to run a locally cloned version of this repo:
```
❯ nix run .#run-vm-jenkins-controller-ephemeral
```

Make sure to also read the section [Secrets](#secrets) to understand how secrets are used and deployed in the examples on this flake.

## Demo

```
❯ nix flake show
├───apps
...
│   └───x86_64-linux
│       ├───run-vm-builder: app: no description
│       ├───run-vm-builder-demo: app: no description
│       ├───run-vm-jenkins-controller: app: no description
│       └───run-vm-jenkins-controller-ephemeral: app: no description
...

```
On running each target, a disk file (`.qcow2`) will be created on the host's current working directory.
Any state data accumulated on the VM will persist as long as the associated disk file is not removed.
For instance, changes to each virtual machine's `/nix/store` will persist reboots as long as the disk file is not removed between the VM boot cycles.
Similarly, each VM state can be cleared by removing the VM disk file on the host.

Following sections explain the main points demonstrated in each apps target:
- [run-vm-builder-demo](#run-vm-builder-demo)
- [run-vm-builder](#run-vm-builder)
- [run-vm-jenkins-controller](#run-vm-jenkins-controller)
- [run-vm-jenkins-controller-ephemeral](#run-vm-jenkins-controller-ephemeral)


### run-vm-builder-demo
[`run-vm-builder-demo`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/nix/apps.nix#L86) demonstrates running a simple nixos configuration as [qemu-vm.nix](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/qemu-vm.nix) virtual machine:
- No secrets
- [Default qemu configuration](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/vm-nixos-qemu.nix#L2-L4): 2 vcpus, 4GB ram, and max disk size 16GB
- Runs host nixosConfiguration [`vm-builder-x86-demo`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/default.nix#L19).
- Exposes [guest ssh over host port 2322](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/default.nix#L29-L31) with [forwardPorts](https://github.com/NixOS/nixpkgs/blob/02b4c1395f2838b5f10d598a2decc151aec132b1/nixos/modules/virtualisation/qemu-vm.nix#L558).
- Demonstrates [using zramSwap](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/vm-nixos-qemu.nix#L22), see more details [here](https://github.com/NixOS/nixpkgs/blob/e3e32b642a31e6714ec1b712de8c91a3352ce7e1/nixos/modules/config/zram.nix#L22).

Here's how it looks on a diagram after running `nix run .#run-vm-builder-demo`:

<img src="doc/img/vm-builder-demo.svg">
<br />

### run-vm-builder
[`run-vm-builder`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/nix/apps.nix#L82) is otherwise the same as [`run-vm-builder-demo`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/nix/apps.nix#L86) but bumps-up the Qemu [ram, vcpu, and max disk size](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/default.nix#L41-L43). Additionaly, there's a separate [`run-vm-builder`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/default.nix#L59) target for aarch64 to support builder VMs on aarch64 hosts.


### run-vm-jenkins-controller
[`run-vm-jenkins-controller`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/nix/apps.nix#L90) demonstrates running a more complex nixos configuration, including [sops secrets](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L45-L47).
- VM host ssh key is [decrypted](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/nix/apps.nix#L29), and placed on a VM [shared directory](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L58) on invoking the [app entry point](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/nix/apps.nix#L92C19-L92C25) giving the VM a stable ssh key.
From there on, [sops-nix](https://github.com/Mic92/sops-nix) takes care of decrypting the secrets when the guest VM boots-up.
- Runs host nixosConfiguration [`vm-jenkins-controller`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/default.nix#L81) with [`ephemeralBuilders`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/default.nix#L84) set to `false`:
   - `builder` and `hetzarm` are configured as [remote builders](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L216-L217).
   - https://ghaf-dev.cachix.org is configured as [additional trusted nix binary cache](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L293-L295), in addition to nixos.org cache.
   - `max-jobs` [is set to 0](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L283), making nix dispatch all builds to remote builders specified in `/nix/etc/machines` and not build anything locally.

Here's how it looks on a diagram after running `nix run .#run-vm-jenkins-controller`:

<img src="doc/img/vm-jenkins-controller.svg">
<br />

### run-vm-jenkins-controller-ephemeral
[`run-vm-jenkins-controller-ephemeral`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/nix/apps.nix#L94) is otherwise the same as [`run-vm-jenkins-controller`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/nix/apps.nix#L90), but [`ephemeralBuilders`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/default.nix#L114) is set to `true`, making the configuration use ephemeral builder VMs:
   - [Two systemd services](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L223-L257) are configured to deploy x86 and aarch64 ephemeral builders on `builder` and `hetzarm`, and [tunnel the builder ssh ports](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L36) to jenkins-controller local ports [3022](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L235-L236) and [4022](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L253-L254).
   - Instead of using `builder` and `hetzarm` as remote builders directly, the [ephemeral builders](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L311-L327) deployed on the mentioned hosts are [configured as remote builders](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L211-L212).
   - Only the [nixos.org binary cache is configured trusted](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L287-L288). Moreover, [remote builders are not allowed to use downstream binary caches](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L289).
   - `max-jobs` [is set to 0](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L283), making nix dispatch all builds to ephemeral remote builders specified in `/nix/etc/machines`.
   - On the jenkins controller shutdown, the [ephemeral builders are also shutdown](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L33-L41) and all their [state is removed](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L18-L23).

This is how it looks on a diagram after running `nix run .#run-vm-jenkins-controller-ephemeral`:

<img src="doc/img/vm-jenkins-controller-ephemeral.svg">
<br />

## Secrets
For deployment secrets (such as ssh keys used to access the remote builders) this project uses [sops-nix](https://github.com/Mic92/sops-nix).

The general idea is: each host that requires secrets have `secrets.yaml` file that contains the encrypted secrets for that host. As an example, the `secrets.yaml` file for the host jenkins-controller defines a secret [`vedenemo_builder_ssh_key`]( https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/secrets.yaml#L3) which is used by the jenkins-controller VM in [its](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L47) configuration to allow ssh access on the remote builders [`builder.vedenemo.dev`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L337) and [`hetzarm.vedenemo.dev`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L342).
All secrets in `secrets.yaml` can be decrypted with each host's ssh key - sops automatically decrypts the host secrets when the system activates (i.e. on boot or whenever nixos-rebuild switch occurs) and places the decrypted secrets in the configured file paths. An [admin user](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/.sops.yaml#L2-L3) manages the secrets by using the `sops` command line tool.

Each host's private ssh key is also stored as [sops secret](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/secrets.yaml#L1) and automatically [depcrypted](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/nix/apps.nix#L29) on running the associated [apps target](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/nix/apps.nix#L92C19-L92C25). The decrypted `ssh_host_ed25519_key` is made available in the VM via a [directory shared between the host and guest](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L58). Finally, openssh on the guest is configured to [use](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/hosts/jenkins-controller/conf.nix#L63) the `ssh_host_ed25519_key` allowing sops to decrypt the VM secrets, by default under `/run/secrets` when the VM is booted up.

`secrets.yaml` files are created and edited with the `sops` utility. The [`.sops.yaml`](.sops.yaml) file tells sops what secrets get encrypted with what keys.

The `run-vm` app targets in this flake can be run by anyone, but only when run by a user that owns the secret key of one of the age public keys declared in [`.sops.yaml`](.sops.yaml) do the secrets get decrypted. In all other cases, the [user is notified](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/nix/apps.nix#L12-L16) and the VM will boot-up without secrets as shown below:

```bash
❯ nix run .#run-vm-jenkins-controller

[+] Running '/nix/store/ily3g1xirjpda4w0a2vjw2kmhlqkzwcw-run-vm-with-share/bin/run-vm-with-share'
Failed to get the data key required to decrypt the SOPS file.

Group 0: FAILED
  age1h6572ak0520k7jpjtm7rga7nsc480rs8xmql9mfp9g3nultg4ejsup2tjn: FAILED
    - | failed to load age identities: failed to open file: open
      | /home/me/.config/sops/age/keys.txt: no such file or
      | directory

  age1hc6hszepd5xezxkgd3yx74on3scxjm5w6px48m4rq9yj7w6rke7q72zhgn: FAILED
    - | failed to load age identities: failed to open file: open
      | /home/me/.config/sops/age/keys.txt: no such file or
      | directory

Recovery failed because no master key was able to decrypt the file. In
order for SOPS to recover the file, at least one key has to be successful,
but none were.

[+] Failed decrypting sops key: VM will boot-up without secrets

Press any key to continue
```

When run by a user that can decrypt the `ssh_host_ed25519_key` secret for the target VM, sops will install the secrets on boot-up:

```
[root@jenkins-controller:~]# journalctl | grep sops
Mar 13 15:05:11 jenkins-controller stage-2-init: sops-install-secrets: Imported /shared/secrets/ssh_host_ed25519_key as age key with fingerprint age1h6572ak0520k7jpjtm7rga7nsc480rs8xmql9mfp9g3nultg4ejsup2tjn

```
and:
```
[root@jenkins-controller:~]# ls -la /run/secrets/
total 8
drwxr-x--x 2 root keys   0 Mar 13 15:05 .
drwxr-x--x 3 root keys   0 Mar 13 15:05 ..
-r-------- 1 root root 411 Mar 13 15:05 vm_builder_ssh_key
-r-------- 1 root root 387 Mar 13 15:05 vedenemo_builder_ssh_key
```

Following sections provide some details on how to work with sops secrets. All commands are executed in nix devshell, which provides the required tools and some convenient helpers:

```bash
❯ nix develop
...
[sops]

  update-sops-files - Update all sops yaml and json files according to .sops.yaml rules
```

### Generating and adding an admin sops key
You will need a key for your admin user to encrypt and decrypt sops secrets. We will use an age key converted from your ssh ed25519 key:
```bash
# Run in nix devshell on your host
$ mkdir -p ~/.config/sops/age
# if you don't have ed25519 key, generate one with:
$ ssh-keygen -t ed25519 -a 100
# convert the ed25519 key to an age key:
$ ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
# print the age public key
$ ssh-to-age < ~/.ssh/id_ed25519.pub
age18jtr8nw8dw7qqgx0wl2547u805y7m7ay73a8xlhfxedksrujhgrsu5ftwe
```

Add the above age public key to the `.sops.yaml` with your username.


### Generating and adding a server sops key

```bash
# Run in nix devshell on your host
# generate a new ssh server key for the target system:
ssh-keygen -t ed25519 -a 100 -C mytarget -f ~/.ssh/mytarget_id_ed25519
# print the host age public key
$ ssh-to-age < ~/.ssh/mytarget_id_ed25519.pub
age15jhcpmj00hqha52l82vecf7gzr8l3ka3sdt63dx8pzkwdteff5vqs4a6c3
```

Add the above age public key to the `.sops.yaml` with the host name you are planning to use for the VM.

### Adding or modifying secrets
To generate or modify secrets for the given host configuration, run:

```bash
# Run in nix devshell on your host
# This will open the secrets.yaml in an editor:
$ sops hosts/jenkins-controller/secrets.yaml
```
The above command opens an editor, where you can edit the secrets.
Remove the example content, and replace with your secrets, so the content would look something like:

```bash
vm_builder_ssh_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    YOUR_BUILD_FARM_PRIVATE_KEY_HERE_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    -----END OPENSSH PRIVATE KEY-----
ssh_host_ed25519_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    YOUR_SERVER_PRIVATE_KEY_HERE_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    -----END OPENSSH PRIVATE KEY-----
```

When you save and exit the editor, sops will encrypt your secrets and saves them to the file you specified: `hosts/jenkins-controller/secrets.yaml`.
Notice: in the example sops configuration in `.sops.yaml`, all users can decrypt all the secrets. For production setups you would want to apply the principle of least privilege, that is, only allow decryption for the servers or users who need access to the specific secret. See, for instance, [nix-community/infra](https://github.com/nix-community/infra/blob/master/.sops.yaml) for a more complete example.

Now, if you re-run the command `sops hosts/jenkins-controller/secrets.yaml`, sops will again decrypt the file allowing you to modify or add new secrets in an editor.

### Updating all sops files
Nix devshell in this flake provides a helper [`update-sops-files`](https://github.com/tiiuae/ci-vm-example/blob/499b5dd5693eaac0b258a10e7861b8e1fb62227e/nix/devshell.nix#L24-L25) to update all secrets after adding or removing new age keys:

```bash
❯ update-sops-files
+ find . -type f -iname secrets.yaml -exec sops updatekeys --yes '{}' ';'
2025/03/13 15:28:41 Syncing keys for file /.../ci-vm-example/hosts/jenkins-controller/secrets.yaml
2025/03/13 15:28:41 File /.../ci-vm-example/hosts/jenkins-controller/secrets.yaml already up to date
```


## Other considerations

### microvm.nix
We also trialed using [microvm.nix](https://github.com/astro/microvm.nix) instead of the nixpkgs [qemu-vm.nix](https://github.com/NixOS/nixpkgs/blob/ecf6d0c2884d24a6216fd0e15034f455792dbe68/nixos/modules/virtualisation/qemu-vm.nix#L1-L5) (which is what this project is [currently using](https://github.com/tiiuae/ci-vm-example/blob/9fdf2cfe1956a6fcb3a9012bb71b613c01328289/nix/apps.nix#L73)).
The microvm.nix trial is available [here](https://github.com/henrirosten/microvm-example/blob/8b90af8a454b7391bd75dc28dabbc56892a075a2/hosts/default.nix#L90-L117).

In a quick test, we failed to make microvm.nix work with `.qcow2` disks; we would want the disk image to grow as data is added instead of allocating the whole image file upfront. There's a trial [here](https://github.com/henrirosten/microvm-example/blob/8995373aa3da9ff110611a1c7f23403ef4fc2b10/hosts/vm-microvm-qemu.nix#L36) that tries to make microvm.nix work with a `.qcow2` disk, however it would require more work to make it boot properly.

We also failed to make the microvm.nix shares work so that a microvm.nix qemu VM could boot-up with stable ssh key, the same way this project currently does with qemu-vm.nix shares. There's a trial [here](https://github.com/henrirosten/microvm-example/blob/0d123035d2ad88c5d08d843dd48ef3822c3c3926/hosts/vm-microvm-qemu.nix#L29-L36).
