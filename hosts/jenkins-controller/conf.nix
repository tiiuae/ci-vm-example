{
  pkgs,
  self,
  inputs,
  lib,
  ephemeralBuilders,
  ...
}:
let
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
  pipelines = [
    "ghaf-manual"
  ];
  # copies only pipelines declared in pipelines[]
  filteredPipelines = pkgs.runCommand "pipelines" { } ''
    mkdir -p $out
    cp -r ${./pipelines}/modules $out/

    ${pkgs.lib.concatMapStringsSep "\n" (name: ''
      cp ${./pipelines}/${name}.groovy "$out/"
    '') pipelines}
  '';
in
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets.vm_builder_ssh_key.owner = "jenkins";
  sops.secrets.vedenemo_builder_ssh_key.owner = "jenkins";
  imports = [
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
      colorized-logs
      git
      nix
      openssh
    ];
    extraJavaOptions = [
      # Useful when the 'sh' step fails:
      "-Dorg.jenkinsci.plugins.durabletask.BourneShellScript.LAUNCH_DIAGNOSTICS=true"
      # Point to configuration-as-code config
      "-Dcasc.jenkins.config=/etc/jenkins/casc"
      # Disable the initial setup wizard, and the creation of initialAdminPassword.
      "-Djenkins.install.runSetupWizard=false"
      # Allow setting the following possibly undefined parameters
      "-Dhudson.model.ParametersAction.safeParameters=DESC,RELOAD_ONLY"
      # Ensure workspace root dir is what we expect
      ''-Djenkins.model.Jenkins.workspacesDir=$JENKINS_HOME/workspace/\$ITEM_FULL_NAME''
    ];
    plugins =
      let
        manifest = builtins.fromJSON (builtins.readFile ./plugins.json);
        mkJenkinsPlugin =
          {
            name,
            version,
            url,
            sha256,
          }:
          lib.nameValuePair name (
            pkgs.stdenv.mkDerivation {
              inherit name version;
              src = pkgs.fetchurl {
                inherit url sha256;
              };
              phases = "installPhase";
              installPhase = "cp \$src \$out";
            }
          );
      in
      builtins.listToAttrs (map mkJenkinsPlugin manifest);
  };

  environment.etc = lib.mkMerge [
    {
      "jenkins/pipelines".source = filteredPipelines;
      "jenkins/casc/common.yaml".source = ./casc/common.yaml;
    }
  ];

  systemd.services.jenkins = {
    serviceConfig = {
      Restart = "on-failure";
    };
  };

  # Remove all config files from jenkins home before loading the casc.
  # This ensures there's no lingering config from the past,
  # and only what is in the casc is regenerated
  systemd.services.jenkins-config-cleanup = {
    before = [ "jenkins.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "jenkins";
      WorkingDirectory = "/var/lib/jenkins";
    };
    script = # sh
      ''
        rm -f *.xml
        rm -f nodes/*/config.xml
        rm -f jobs/*/config.xml
      '';
  };

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
            echo "ssh://ephemeral-builder x86_64-linux - 20 10 kvm,nixos-test,benchmark,big-parallel" >/etc/nix/machines
            echo "ssh://ephemeral-hetzarm aarch64-linux - 20 10 kvm,nixos-test,benchmark,big-parallel" >>/etc/nix/machines
          ''
        else
          ''
            echo "ssh://builder.vedenemo.dev x86_64-linux - 20 10 kvm,nixos-test,benchmark,big-parallel" >/etc/nix/machines
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
      remote="builder.vedenemo.dev"
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
          trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
          substituters = https://cache.nixos.org
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
    knownHosts."builder.vedenemo.dev".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG68NdmOw3mhiBZwDv81dXitePoc1w//p/LpsHHA8QRp";
    knownHosts."hetzarm.vedenemo.dev".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILx4zU4gIkTY/1oKEOkf9gTJChdx/jR3lDgZ7p/c7LEK";

    # Custom options to /etc/ssh/ssh_config
    extraConfig = lib.mkAfter ''
      # VM we spin-up on builder.vedenemo.dev with builder-vm-x86-start service
      Host ephemeral-builder
      Hostname localhost
      Port 3022
      User vm-builder
      IdentityFile /run/secrets/vm_builder_ssh_key
      # We check the builder.vedenemo.dev key already
      StrictHostKeyChecking no

      # VM we spin-up on hetzarm.vedenemo.dev with builder-vm-aarch-start service
      Host ephemeral-hetzarm
      Hostname localhost
      Port 4022
      User vm-builder
      IdentityFile /run/secrets/vm_builder_ssh_key
      # We check the hetzarm.vedenemo.dev key already
      StrictHostKeyChecking no

      Host builder.vedenemo.dev
      Hostname builder.vedenemo.dev
      User remote-build
      IdentityFile /run/secrets/vedenemo_builder_ssh_key

      Host hetzarm.vedenemo.dev
      Hostname hetzarm.vedenemo.dev
      User remote-build
      IdentityFile /run/secrets/vedenemo_builder_ssh_key
    '';
  };
}
