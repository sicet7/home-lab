# Original config is from here: https://nixos.wiki/wiki/Proxmox_Linux_Container
{ config, modulesPath, pkgs, lib, ... }:
let
  cronExpr = "0 3 * * 0";
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

    set -e


    LOCAL_MOUNTPOINT="$1"
    DB_HOST="$2"
    DB_PORT="$3"
    DB_USERNAME="$4"

    if [ -z "$LOCAL_MOUNTPOINT" ]; then
      echo "Mountpoint not found: $LOCAL_MOUNTPOINT"
      exit 1;
    fi

    DUMP_PATH="$LOCAL_MOUNTPOINT/$(date +"%Y-week_%U")"   
    
    mkdir -p "$DUMP_PATH"

    DUMP_FILEPATH="$DUMP_PATH/pg_dump_all_$(date +"%Y-%m-%d_%H-%M-%S").sql.gz"

    export PATH=${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.gzip}/bin:${pkgs.postgresql_17}/bin
    export HOME=/root

    ${pkgs.postgresql_17}/bin/pg_dumpall --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USERNAME" --no-password | gzip > "$DUMP_FILEPATH"

  '';
in
{
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];
  nix.settings = { sandbox = false; };  
  proxmoxLXC = {
    manageNetwork = false;
    privileged = true;
  };
  security.pam.services.sshd.allowNullPassword = true;
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
        PermitRootLogin = "yes";
        PasswordAuthentication = true;
        PermitEmptyPasswords = "yes";
    };
  };
  environment.systemPackages = [
    pkgs.postgresql_17
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
      "${cronExpr}      root    ${backupScript} \"${nfs.localMountpoint}\" \"${db.host}\" \"${db.port}\" \"${db.username}\""
    ];
  };
  boot.supportedFilesystems = [ "nfs" ];
  system.stateVersion = "24.11";
}
