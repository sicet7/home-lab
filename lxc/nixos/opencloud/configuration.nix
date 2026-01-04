{ config, modulesPath, pkgs, lib, ... }:
let
  nfs = {
    remoteHost = "<nfs-remote-host>";
    localMountpoint = "<nfs-local-mountpoint>";
    remoteMountpoint = "<nfs-remote-mountpoint>";
  };
  opencloud = {
    domain = "<opencloud-domain>";
    oidcIssuer = "<oidc-issuer-url>";
    initialAdminPassword = "<init-admin-password>";
    idpDomain = "<idp-domain>";
    collaboraDomain = "<collabora-domain>";
    companionDomain = "<companion-domain>";
    wopiserverDomain = "<wopiserver-domain>";
    idpClientId = "<idp-client-id>";
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
    allowedTCPPorts = [ 9200 9980 9300 ];
    allowedUDPPorts = [ 9200 9980 9300 ];
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

      OC_CONFIG_DIR = "${nfs.localMountpoint}/config";
      OC_DATA_DIR = "${nfs.localMountpoint}/data";
      OC_DOMAIN = "${opencloud.domain}";
      OC_URL = "https://${opencloud.domain}";
      OC_INSECURE = "true";
      PROXY_TLS = "false";
      IDM_ADMIN_PASSWORD = "${opencloud.initialAdminPassword}";
      HOME = "/var/empty";
      PROXY_AUTOPROVISION_ACCOUNTS = "true";
      PROXY_AUTOPROVISION_CLAIM_USERNAME = "opencloud_username";
      PROXY_AUTOPROVISION_CLAIM_EMAIL = "email";
      PROXY_AUTOPROVISION_CLAIM_DISPLAYNAME = "name";
      OC_EXCLUDE_RUN_SERVICES = "idp";
      OC_OIDC_ISSUER = "${opencloud.oidcIssuer}";
      OC_OIDC_CLIENT_ID = "${opencloud.idpClientId}";
      PROXY_OIDC_REWRITE_WELLKNOWN = "true";
      PROXY_ROLE_ASSIGNMENT_OIDC_CLAIM = "opencloud_role";
      PROXY_USER_OIDC_CLAIM = "sub";
      PROXY_USER_CS3_CLAIM = "userid";
      PROXY_ENABLE_BASIC_AUTH = "false";
      PROXY_INSECURE_BACKENDS = "false";
      PROXY_CSP_CONFIG_FILE_LOCATION = "/etc/opencloud/csp.yaml";
      PROXY_ROLE_ASSIGNMENT_DRIVER = "oidc";
      GRAPH_ASSIGN_DEFAULT_USER_ROLE = "false";

#      NOTIFICATIONS_SMTP_HOST = "${smtp.host}";
#      NOTIFICATIONS_SMTP_PORT = "${smtp.port}";
#      NOTIFICATIONS_SMTP_SENDER = "${smtp.sender}";
#      NOTIFICATIONS_SMTP_USERNAME = "${smtp.username}";
#      NOTIFICATIONS_SMTP_PASSWORD = "${smtp.password}";
#      NOTIFICATIONS_SMTP_INSECURE = "${smtp.insecure}";
#      NOTIFICATIONS_SMTP_AUTHENTICATION = "${smtp.authentication}";
#      NOTIFICATIONS_SMTP_ENCRYPTION = "${smtp.encryption}";
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

  environment.etc."opencloud/csp.yaml".text = ''
    directives:
      child-src:
        - '''self'''
      connect-src:
        - '''self'''
        - 'blob:'
        - 'https://${opencloud.companionDomain}/'
        - 'wss://${opencloud.companionDomain}/'
        - 'https://raw.githubusercontent.com/opencloud-eu/awesome-apps/'
        - 'https://${opencloud.idpDomain}/'
        - 'https://update.opencloud.eu/'
      default-src:
        - '''none'''
      font-src:
        - '''self'''
      frame-ancestors:
        - '''self'''
      frame-src:
        - '''self'''
        - 'blob:'
        - 'https://embed.diagrams.net/'
        # In contrary to bash and docker the default is given after the | character
        - 'https://${opencloud.collaboraDomain}/'
        # This is needed for the external-sites web extension when embedding sites
        - 'https://docs.opencloud.eu'
      img-src:
        - '''self'''
        - 'data:'
        - 'blob:'
        - 'https://raw.githubusercontent.com/opencloud-eu/awesome-apps/'
        - 'https://tile.openstreetmap.org/'
        # In contrary to bash and docker the default is given after the | character
        - 'https://${opencloud.collaboraDomain}/'
      manifest-src:
        - '''self'''
      media-src:
        - '''self'''
      object-src:
        - '''self'''
        - 'blob:'
      script-src:
        - '''self'''
        - '''unsafe-inline'''
        - 'https://${opencloud.idpDomain}/'
      style-src:
        - '''self'''
        - '''unsafe-inline'''
  '';

  system.stateVersion = "25.11";
}
