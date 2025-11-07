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

  services.resolved.extraConfig = ''
    Cache=true
    CacheFromLocalhost=true
  '';

  virtualisation.docker.enable = true;

  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      peanut = {
        image = "brandawg93/peanut:latest";
        ports = [ "80:8080" ];
        volumes = [
          "/var/lib/peanut:/config"
        ];
        environment = {
          WEB_HOST = "0.0.0.0";
          WEB_PORT = "8080";
          DISABLE_CONFIG_FILE = "true";
          NUT_SERVERS = ''[{"HOST":"10.25.25.2","PORT":3493,"USERNAME":"readonly","PASSWORD":"password1","DISABLED":false}]'';
          DATE_FORMAT = "DD/MM/YYYY";
          TIME_FORMAT = "24-hour";
          DEBUG = "false";
          DASHBOARD_SECTIONS = ''[
            {"key":"KPIS","enabled":true},
            {"key":"CHARTS","enabled":true},
            {"key":"VARIABLES","enabled":true}
          ]'';
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/peanut 0755 root root -"
  ];

  system.stateVersion = "25.05";
}
