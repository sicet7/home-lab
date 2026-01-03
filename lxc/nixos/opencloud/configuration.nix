{ config, modulesPath, pkgs, lib, ... }:
let
  nfs = {
    remoteHost = "<nfs-remote-host>";
    localMountpoint = "<nfs-local-mountpoint>";
    remoteMountpoint = "<nfs-remote-mountpoint>";
  };
  opencloud = {
    domain = "<opencloud-url>";
    oidcIssuer = "<oidc-issuer-url>";
    initialAdminPassword = "<init-admin-password>";
    idpDomain = "<idp-domain>";
  };
  smtp = {
    host = "<smtp-host>";
    port = "<smtp-port>";
    sender = "<smtp-sender>";
    username = "<smtp-username>";
    password = "<smtp-password>";
    insecure = "false";
    authentication = "<smtp-authentication>"; # Possible values are 'login', 'plain', 'crammd5', 'none' or 'auto'. If set to 'auto' or unset, the authentication method is automatically negotiated with the server.
    encryption = "<smtp-encryption>"; # Possible values are 'starttls', 'ssltls' and 'none'.
  };
in
{ 
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];

  nixpkgs.config.allowUnfree = true;

  fonts = {
    fontconfig.enable = true;

    packages = with pkgs; [
      corefonts
      liberation_ttf
      noto-fonts
      noto-fonts-cjk
    ];
  };

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

  fileSystems."${nfs.localMountpoint}" = {
    device = "${nfs.remoteHost}:${nfs.remoteMountpoint}";
    fsType = "nfs";
  };

  boot.supportedFilesystems = [ "nfs" ];

  environment.systemPackages = [
    pkgs.opencloud
  ];

  users.groups.opencloud = {
    gid = 1000;
  };

  users.users.opencloud = {
    isNormalUser = false;
    isSystemUser = true;
    uid = 1000;

    group = "opencloud";
    home = "/var/empty";
    createHome = false;
  };

  systemd.tmpfiles.rules = [
    "d ${nfs.localMountpoint}/config 0750 opencloud opencloud -"
    "d ${nfs.localMountpoint}/data   0750 opencloud opencloud -"
  ];

  systemd.services.opencloud = {
    description = "OpenCloud Server";
    wantedBy = [ "multi-user.target" ];

    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      IDM_CREATE_DEMO_USERS = "false";
      PROXY_ENABLE_BASIC_AUTH = "false";
      OC_CONFIG_DIR = "${nfs.localMountpoint}/config";
      OC_DATA_DIR = "${nfs.localMountpoint}/data";
      OC_DOMAIN = "${opencloud.domain}";
      OC_URL = "https://${opencloud.domain}";
      OC_INSECURE = "true";
      PROXY_TLS = "false";
      IDM_ADMIN_PASSWORD = "${opencloud.initialAdminPassword}";
      HOME = "/var/empty";
#      OC_EXCLUDE_RUN_SERVICES = "idp";
#      OC_OIDC_ISSUER = "${opencloud.oidcIssuer}";

      NOTIFICATIONS_SMTP_HOST = "${smtp.host}";
      NOTIFICATIONS_SMTP_PORT = "${smtp.port}";
      NOTIFICATIONS_SMTP_SENDER = "${smtp.sender}";
      NOTIFICATIONS_SMTP_USERNAME = "${smtp.username}";
      NOTIFICATIONS_SMTP_PASSWORD = "${smtp.password}";
      NOTIFICATIONS_SMTP_INSECURE = "${smtp.insecure}";
      NOTIFICATIONS_SMTP_AUTHENTICATION = "${smtp.authentication}";
      NOTIFICATIONS_SMTP_ENCRYPTION = "${smtp.encryption}";
    };

    serviceConfig = {
      Type = "simple";

      User  = "opencloud";
      Group = "opencloud";

      RequiresMountsFor = [ nfs.localMountpoint ];

      ExecStartPre = [
        "-${pkgs.opencloud}/bin/opencloud init"
      ];

      ExecStart = "${pkgs.opencloud}/bin/opencloud server";
      Restart = "on-failure";
      RestartSec = "2s";
    };
  };

  system.stateVersion = "25.11";
}
