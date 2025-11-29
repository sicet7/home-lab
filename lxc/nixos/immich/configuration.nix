{ config, modulesPath, pkgs, lib, ... }:
let
  immich = {
    host = "0.0.0.0";
    port = "2283";
    trustedProxies = "<trusted-proxies>";
  };
  db = {
    host = "<db-host>";
    port = "<db-port>";
    username = "<db-username>";
    password = "<db-password>";
    name = "<db-name>";
  };
  nfs = {
    remoteHost = "<nfs-remote-host>";
    localMountpoint = "<nfs-local-mountpoint>";
    remoteMountpoint = "<nfs-remote-mountpoint>";
  };
in
{
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];

  nix.settings = { sandbox = false; };

  proxmoxLXC = {
    manageNetwork = false;
    privileged = true;
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [  ];
    allowedUDPPorts = [  ];
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
  
  virtualisation.docker.enable = true;
  
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      redis = {
        autoStart = true;
        hostname = "redis";
        image = "docker.io/valkey/valkey:8@sha256:81db6d39e1bba3b3ff32bd3a1b19a6d69690f94a3954ec131277b9a26b95b3aa";
        extraOptions = [
          "--network=immich"
        ];
      };
      immich = {
        autoStart = true;
        hostname = "immich";
        image = "ghcr.io/immich-app/immich-server:v2";
        dependsOn = [ "redis" ];
        environment = {
          TZ = "Europe/Copenhagen";
          NO_COLOR = "true";
          CPU_CORES = "10";
          IMMICH_ENV = "production";
          IMMICH_TRUSTED_PROXIES = "${immich.trustedProxies}";
          IMMICH_HOST = "${immich.host}";
          IMMICH_PORT = "${immich.port}";
          IMMICH_MEDIA_LOCATION = "/data";
          
          DB_HOSTNAME = "${db.host}";
          DB_PORT = "${db.port}";
          DB_USERNAME = "${db.username}";
          DB_PASSWORD = "${db.password}";
          DB_DATABASE_NAME = "${db.name}";
          DB_VECTOR_EXTENSION = "vectorchord";
          DB_SKIP_MIGRATIONS = "false";
          
          REDIS_HOSTNAME = "redis";
          REDIS_PORT = "6379";
          REDIS_DBINDEX = "0";
          
        };
        ports = [
          "${immich.port}:${immich.port}"
        ];
        volumes = [
          "${nfs.localMountpoint}:/data"
          "/etc/localtime:/etc/localtime:ro"
        ];
        extraOptions = [
          "--network=immich"
        ];
      };
    };
  };

  systemd.services.create-docker-network = with config.virtualisation.oci-containers; {
    serviceConfig.Type = "oneshot";
    wants = [ "${backend}.service" ];
    wantedBy = [ "${backend}-immich.service" ];
    script = ''
      ${pkgs.docker}/bin/docker network inspect immich >/dev/null 2>&1 || \
      ${pkgs.docker}/bin/docker network create --driver bridge immich
    '';
  };

  fileSystems."${nfs.localMountpoint}" = {
    device = "${nfs.remoteHost}:${nfs.remoteMountpoint}";
    fsType = "nfs";
  };

  boot.supportedFilesystems = [ "nfs" ];

  system.stateVersion = "25.05";
}
