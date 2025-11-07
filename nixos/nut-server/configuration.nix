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

  environment.systemPackages = with pkgs; [ nut usbutils ];

  environment.etc."nut/admin.pass".text = ''
    password1
  '';
  environment.etc."nut/readonly.pass".text = ''
    password2
  '';

  users.groups.nut = { };
  users.users.nut = { isSystemUser = true; group = "nut"; };
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="0764", ATTR{idProduct}=="0601", MODE="0660", GROUP="nut"
    KERNEL=="hidraw*", ATTRS{idVendor}=="0764", ATTRS{idProduct}=="0601", MODE="0660", GROUP="nut"
  '';

  power.ups = {
    enable = true;

    mode = "netserver";

    ups.powerwalker = {
      driver = "usbhid-ups";
      port = "auto";
      description = "Powerwalker Vi 3000 Rle 3000VA 1800W";
      directives = [
        "vendorid = 0764"
        "productid = 0601"
        "pollinterval = 1"
        "maxretry = 3"
      ];
    };

    upsd = {
      enable = true;
      extraConfig = ''
        LISTEN 0.0.0.0 3493
      '';
    };

    users.admin = {
      upsmon = "primary";
      passwordFile = "/etc/nut/admin.pass";
    };

    users.readonly = {
      upsmon = "secondary";
      passwordFile = "/etc/nut/readonly.pass";
    };

    upsmon = {
      enable = true;
      settings = {
        RUN_AS_USER = "root";
      };
      monitor.powerwalker = {
        system = "powerwalker@localhost";
        powerValue = 1;
        user = "admin";
        type = "primary";
        passwordFile = "/etc/nut/admin.pass";
      };
    };

    openFirewall = true;
  };


  system.stateVersion = "25.05";
}
