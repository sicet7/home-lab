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

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 80 ];
  networking.firewall.allowedUDPPorts = [ 80 ];

  virtualisation = {
    docker.enable = true;

    oci-containers = {
      backend = "docker";
      containers = {
        uptime-kuma = {
          autoStart = true;
          hostname = "uptime-kuma";
          image = "louislam/uptime-kuma:2";

          environment = {
            UPTIME_KUMA_PORT = "80";
          };

          volumes = [
            "/docker/uptime-kuma:/app/data"
          ];

          ports = [
            "80:80"
          ];
        };
      };
    };
  };

  system.stateVersion = "25.05";
}
