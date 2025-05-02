{
  pkgs,
  self,
  inputs,
  lib,
  ephemeralBuilders,
  ...
}:
let
  jenkins-casc = ./casc;
  run-builder-vm = pkgs.writeShellScript "run-builder-vm" ''
    set -eu
    remote="$1"
    nix_target="$2"
    local_port="$3"
    TMPWORKDIR="$(mktemp --dry-run --directory --suffix .nix-vm-builder)"
    echo "Using TMPWORKDIR '$TMPWORKDIR' on remote '$remote'"
    on_exit () {
      set -x
      echo "Removing '$TMPWORKDIR' on '$remote'"
      ${pkgs.openssh}/bin/ssh "$remote" "rm -fr $TMPWORKDIR || echo Failed"
    }
    trap on_exit EXIT

    # Copy the flake source from /shared/source over to remote at TMPWORKDIR
    # so we can nix run the nix_target on remote
    ${pkgs.openssh}/bin/scp -r /shared/source "$remote":"$TMPWORKDIR"

    # Run the builder vm on the remote over ssh, forwarding the
    # 'localhost:local_port' over to remote port '2322'. After builder vm
    # boots-up, its ssh service is available on remote:2322 so this allows
    # reaching the remote builder over ssh at localhost:local_port.
    # The '-tt' option causes the remote process (nix run ...) to terminate
    # when the below ssh process is terminated.
    echo "Starting builder vm '$nix_target' - ssh at local port '$local_port'"
    ${pkgs.openssh}/bin/ssh -L "$local_port":localhost:2322 "$remote" -tt \
    "\
      export TMPDIR="$TMPWORKDIR"
      cd "$TMPWORKDIR";\
      nix run --refresh .#"$nix_target";\
    ";
  '';
in
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets.vm_builder_ssh_key.owner = "jenkins";
  sops.secrets.vedenemo_builder_ssh_key.owner = "jenkins";
  imports =
    [
      inputs.sops-nix.nixosModules.sops
    ]
    ++ (with self.nixosModules; [
      hosts-common
      user-hrosten
    ]);

  virtualisation.vmVariant.virtualisation.sharedDirectories.shr = {
    source = "$HOME/.config/vmshared/jenkins-controller";
    target = "/shared";
  };
  virtualisation.vmVariant.services.openssh.hostKeys = [
    {
      path = "/shared/secrets/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  networking = {
    hostName = "jenkins-controller";
    firewall.allowedTCPPorts = [
      8081
    ];
  };
  # We run nix-fast-build from jenkins pipeline, which runs as jenkins user.
  # If we want the nix-fast-build to be able to download the build results
  # (write to local nix store), we need to make jenkins a trusted nix user.
  nix.settings.trusted-users = [ "jenkins" ];
  services.jenkins = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 8081;
    withCLI = true;
    packages = with pkgs; [
      bashInteractive # 'sh' step in jenkins pipeline requires this
      coreutils
      git
      nix
      openssh
    ];
    extraJavaOptions = [
      # Useful when the 'sh' step fails:
      "-Dorg.jenkinsci.plugins.durabletask.BourneShellScript.LAUNCH_DIAGNOSTICS=true"
      # Point to configuration-as-code config
      "-Dcasc.jenkins.config=${jenkins-casc}"
    ];
    plugins = import ./plugins.nix { inherit (pkgs) stdenv fetchurl; };
  };

  systemd.services.jenkins-pipeline-copy = {
    before = [ "jenkins.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
    };
    path = with pkgs; [ rsync ];
    script = ''
      rsync -a --perms --chmod=D700,F400 --chown=jenkins:jenkins \
        /shared/source/hosts/jenkins-controller/casc/pipelines /tmp/
      ${
        if ephemeralBuilders then
          ''
            rm /tmp/pipelines/ghaf-slim-demo-cached.groovy
          ''
        else
          ''
            rm /tmp/pipelines/ghaf-slim-demo-ephemeral.groovy
          ''
      }
    '';
  };

  systemd.services.jenkins = {
    # Make `jenkins-cli` available
    path = with pkgs; [ jenkins ];
    # Implicit URL parameter for `jenkins-cli`
    environment = {
      JENKINS_URL = "http://localhost:8081";
    };
    postStart =
      let
        jenkins-auth = "-auth admin:\"$(cat /var/lib/jenkins/secrets/initialAdminPassword)\"";
        # Disable setup wizard and restart
        jenkins-init = pkgs.writeText "groovy" ''
          #!groovy
          import jenkins.model.*
          import jenkins.install.*
          Jenkins.getInstance().setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
          Jenkins.getInstance().save()
          Jenkins.getInstance().restart()
        '';
        # Trigger all pipelines
        jenkins-trigger-all = pkgs.writeText "groovy" ''
          #!groovy
          import jenkins.model.*
          import hudson.model.*
          for (job in Jenkins.getInstance().getAllItems(Job)) {
            println("Triggering job: " + job.getName())
            job.scheduleBuild(0);
          }
        '';
      in
      ''
        echo "Waiting jenkins to become online"
        until jenkins-cli ${jenkins-auth} who-am-i >/dev/null 2>&1; do sleep 1; done
        echo "Disable setup wizard and restart jenkins"
        jenkins-cli ${jenkins-auth} groovy = < ${jenkins-init}
        echo "Waiting jenkins to shutdown"
        until ! jenkins-cli ${jenkins-auth} who-am-i >/dev/null 2>&1; do sleep 1; done
        echo "Waiting jenkins to restart"
        until jenkins-cli ${jenkins-auth} who-am-i >/dev/null 2>&1; do sleep 1; done
        echo "Triggering jenkins jobs"
        jenkins-cli ${jenkins-auth} groovy = < ${jenkins-trigger-all}
      '';
    serviceConfig = {
      Restart = "on-failure";
    };
  };

  # set StateDirectory=jenkins, so state volume has the right permissions
  # and we wait on the mountpoint to appear.
  # https://github.com/NixOS/nixpkgs/pull/272679
  systemd.services.jenkins.serviceConfig.StateDirectory = "jenkins";

  systemd.services.populate-builder-machines = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
    };
    script = ''
      # If this is not the first time this instance of jenkins-controller
      # boots-up, the ephemeral builders' public keys from the pervious power
      # cycle might still be around in /root/.ssh/known_hosts. Since we
      # spin-up new ephemeral builders every time jenkins-controller
      # boots-up, we also need to clean the /root/.ssh/known_hosts
      rm -fr /root/.ssh/known_hosts

      mkdir -p /etc/nix
      ${
        if ephemeralBuilders then
          ''
            echo "ssh://ephemeral-build2 x86_64-linux - 20 10 kvm,nixos-test,benchmark,big-parallel" >/etc/nix/machines
            echo "ssh://ephemeral-hetzarm aarch64-linux - 20 10 kvm,nixos-test,benchmark,big-parallel" >>/etc/nix/machines
          ''
        else
          ''
            echo "ssh://build2.vedenemo.dev x86_64-linux - 20 10 kvm,nixos-test,benchmark,big-parallel" >/etc/nix/machines
            echo "ssh://hetzarm.vedenemo.dev aarch64-linux - 20 10 kvm,nixos-test,benchmark,big-parallel" >>/etc/nix/machines
          ''
      }
    '';
  };

  systemd.services.builder-vm-x86-start = {
    after = [ "network-online.target" ];
    before = [ "nix-daemon.service" ];
    requires = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "exec";
      RemainAfterExit = true;
      # Replace "no" with "always" to enable the below mentioned restart logic.
      # Restart is disabled currently to prevent fail2ban from blocking us
      # in case of failure.
      Restart = "no";
      # Try re-start at 30 seconds intervals.
      # If there are more than 3 restart attempts in a 240 second interval,
      # wait for the 240 second interval to pass before another re-try.
      RestartSec = 30;
      StartLimitBurst = 3;
      StartLimitIntervalSec = 240;
    };
    script = ''
      remote="build2.vedenemo.dev"
      nix_target="apps.x86_64-linux.run-vm-builder"
      local_port="3022"
      ${run-builder-vm} "$remote" "$nix_target" "$local_port"
    '';
    enable = if ephemeralBuilders then true else false;
  };

  systemd.services.builder-vm-aarch-start = {
    after = [ "network-online.target" ];
    before = [ "nix-daemon.service" ];
    requires = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "exec";
      RemainAfterExit = true;
      # Replace "no" with "always" to enable the below mentioned restart logic.
      # Restart is disabled currently to prevent fail2ban from blocking us
      # in case of failure.
      Restart = "no";
      # Try re-start at 30 seconds intervals.
      # If there are more than 3 restart attempts in a 240 second interval,
      # wait for the 240 second interval to pass before another re-try.
      RestartSec = 30;
      StartLimitBurst = 3;
      StartLimitIntervalSec = 240;
    };
    script = ''
      remote="hetzarm.vedenemo.dev"
      nix_target="apps.aarch64-linux.run-vm-builder"
      local_port="4022"
      ${run-builder-vm} "$remote" "$nix_target" "$local_port"
    '';
    enable = if ephemeralBuilders then true else false;
  };

  # Enable early out-of-memory killing.
  # Make nix builds more likely to be killed over more important services.
  services.earlyoom = {
    enable = true;
    # earlyoom sends SIGTERM once below 5% and SIGKILL when below half
    # of freeMemThreshold
    freeMemThreshold = 5;
    extraArgs = [
      "--prefer"
      "^(nix-daemon)$"
      "--avoid"
      "^(java|jenkins-.*|sshd|systemd|systemd-.*)$"
    ];
  };
  # Tell the Nix evaluator to garbage collect more aggressively
  environment.variables.GC_INITIAL_HEAP_SIZE = "1M";
  # Always overcommit: pretend there is always enough memory
  # until it actually runs out
  boot.kernel.sysctl."vm.overcommit_memory" = "1";

  nix.extraOptions = ''
    connect-timeout = 5
    system-features = nixos-test benchmark big-parallel kvm
    builders = @/etc/nix/machines
    max-jobs = 0
    ${
      if ephemeralBuilders then
        ''
          substituters = none
          trusted-public-keys = none
          substitute = false
          builders-use-substitutes = false
        ''
      else
        ''
          trusted-public-keys = ghaf-dev.cachix.org-1:S3M8x3no8LFQPBfHw1jl6nmP8A7cVWKntoMKN3IsEQY= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
          substituters = https://ghaf-dev.cachix.org https://cache.nixos.org
          builders-use-substitutes = true
        ''
    }
  '';
  programs.ssh = {

    # Known builder host public keys, these go to /root/.ssh/known_hosts
    knownHosts."build2.vedenemo.dev".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILL40b7SbAcL1MK3D5U9IgVRR87myFLTzVdryQnVqb7p";
    knownHosts."hetzarm.vedenemo.dev".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILx4zU4gIkTY/1oKEOkf9gTJChdx/jR3lDgZ7p/c7LEK";

    # Custom options to /etc/ssh/ssh_config
    extraConfig = lib.mkAfter ''
      # VM we spin-up on build2.vedenemo.dev with builder-vm-x86-start service
      Host ephemeral-build2
      Hostname localhost
      Port 3022
      User vm-builder
      IdentityFile /run/secrets/vm_builder_ssh_key
      # We check the build2.vedenemo.dev key already
      StrictHostKeyChecking no

      # VM we spin-up on hetzarm.vedenemo.dev with builder-vm-aarch-start service
      Host ephemeral-hetzarm
      Hostname localhost
      Port 4022
      User vm-builder
      IdentityFile /run/secrets/vm_builder_ssh_key
      # We check the hetzarm.vedenemo.dev key already
      StrictHostKeyChecking no

      Host build2.vedenemo.dev
      Hostname build2.vedenemo.dev
      User remote-build
      IdentityFile /run/secrets/vedenemo_builder_ssh_key

      Host hetzarm.vedenemo.dev
      Hostname hetzarm.vedenemo.dev
      User remote-build
      IdentityFile /run/secrets/vedenemo_builder_ssh_key
    '';
  };
}
