{ config, modulesPath, pkgs, lib, ... }: 
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

  system.stateVersion = "25.05";
}
