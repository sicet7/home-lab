{ config, modulesPath, pkgs, lib, ... }:
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

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 5432 ];
    allowedUDPPorts = [ 5432 ];
  };

  services.resolved.extraConfig = ''
    Cache=true
    CacheFromLocalhost=true
  '';

  services.postgresql = {
    enable = true;
    enableTCPIP = true;

    package = pkgs.postgresql_17;

    extensions = ps: [ ps.vectorchord ];

    settings.password_encryption = "scram-sha-256";

    authentication = lib.mkForce ''
      # Local socket connections
      local   all             postgres                                peer
      local   all             all                                     scram-sha-256

      # IPv4 localhost
      host    all             all             127.0.0.1/32            scram-sha-256

      # IPv6 localhost
      host    all             all             ::1/128                 scram-sha-256

      # LAN: 10.25.25.0/24
      host    all             all             10.25.25.0/24           scram-sha-256
      host    all             all             10.27.27.0/24           scram-sha-256

      # Replication
      local   replication     all                                     peer
      host    replication     all             127.0.0.1/32            scram-sha-256
      host    replication     all             ::1/128                 scram-sha-256
    '';

    initialScript = pkgs.writeText "postgres-init.sql" ''
        \c template1;
        CREATE EXTENSION IF NOT EXISTS vectorchord;
    '';
  };

  system.stateVersion = "25.05";
}
