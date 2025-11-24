{ config, modulesPath, pkgs, lib, ... }:
let
  cronExpr = "0 23 * * *";
  uptimeUrl = "<uptime-kuma-url>";
  db = {
    host = "<db-host>";
    port = "<db-port>";
    username = "<db-username>";
    password = "<db-password>";
  };
  nfs = {
    remoteHost = "<nfs-remote-host>";
    localMountpoint = "<nfs-local-mountpoint>";
    remoteMountpoint = "<nfs-remote-mountpoint>";
  };
  backupScript = pkgs.writeShellScript "pg-backup-script" ''
    #!${pkgs.bash}/bin/bash

    set -euo pipefail

    LOCAL_MOUNTPOINT="$1"
    DB_HOST="$2"
    DB_PORT="$3"
    DB_USERNAME="$4"
    UPTIME_URL="$5"

    if [ -z "$LOCAL_MOUNTPOINT" ]; then
      echo "Mountpoint not found: $LOCAL_MOUNTPOINT"
      exit 1;
    fi

    DUMP_PATH="$LOCAL_MOUNTPOINT/$(date +"%Y")/$(date +"%m")/$(date +"%d")"

    mkdir -p "$DUMP_PATH"

    DUMP_FILEPATH="$DUMP_PATH/pg_dump_all_$(date +"%H-%M-%S").sql.gz"

    export PATH=${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.gzip}/bin:${pkgs.postgresql_17}/bin
    export HOME=/root

    ${pkgs.postgresql_17}/bin/pg_dumpall --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USERNAME" --no-password | gzip > "$DUMP_FILEPATH"

    ${pkgs.curl}/bin/curl -s -o /dev/null "$UPTIME_URL"
  '';
in
{
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];

  nix.settings = { sandbox = false; };

  proxmoxLXC = {
    manageNetwork = false;
    privileged = true;
  };

  security.pam.services.sshd.allowNullPassword = lib.mkForce false;
  services.fstrim.enable = false;
  services.openssh = {
    enable = false;
    openFirewall = false;
  };

  services.resolved.extraConfig = ''
    Cache=true
    CacheFromLocalhost=true
  '';

  environment.systemPackages = [
    pkgs.postgresql_17
    pkgs.curl
  ];
  system.activationScripts.writePgPass.text = ''
    echo "*:*:*:*:${db.password}" > /root/.pgpass
    chown root:root /root/.pgpass
    chmod 600 /root/.pgpass
  '';
  fileSystems."${nfs.localMountpoint}" = {
    device = "${nfs.remoteHost}:${nfs.remoteMountpoint}";
    fsType = "nfs";
  };
  services.cron = {
    enable = true;
    systemCronJobs = [
      "${cronExpr}      root    ${backupScript} \"${nfs.localMountpoint}\" \"${db.host}\" \"${db.port}\" \"${db.username}\" \"${uptimeUrl}\""
    ];
  };
  boot.supportedFilesystems = [ "nfs" ];
  system.stateVersion = "25.05";
}