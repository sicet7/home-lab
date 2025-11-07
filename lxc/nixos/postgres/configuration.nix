# Original config is from here: https://nixos.wiki/wiki/Proxmox_Linux_Container
{ config, modulesPath, pkgs, lib, ... }:
{
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];
  nix.settings = { sandbox = false; };
  proxmoxLXC = {
    manageNetwork = false;
    privileged = false;
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
  config.services.postgresql = {
    enable = true;
    enableTCPIP = true;
    package = pkgs.postgresql_17;
    authentication = pkgs.lib.mkOverride 10 ''
      # PostgreSQL Client Authentication Configuration File
      local   all             postgres                                peer
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      # "local" is for Unix domain socket connections only
      local   all             all                                     md5
      # IPv4 local connections:
      host    all             all             127.0.0.1/32            scram-sha-256
      host    all             all             0.0.0.0/24              md5
      # IPv6 local connections:
      host    all             all             ::1/128                 scram-sha-256
      host    all             all             0.0.0.0/0               md5
      # Allow replication connections from localhost, by a user with the
      # replication privilege.
      local   replication     all                                     peer
      host    replication     all             127.0.0.1/32            scram-sha-256
      host    replication     all             ::1/128                 scram-sha-256
    '';
  };
  system.stateVersion = "24.11";
}