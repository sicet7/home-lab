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

  virtualisation.docker.enable = true;

  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      opencloud = {
        autoStart = true;
        hostname = "opencloud";
        image = "docker.io/opencloudeu/opencloud-rolling:4.1";
#        dependsOn = [ "redis" ];
        environment = {


        };
        ports = [ ];
        volumes = [
          "${nfs.localMountpoint}/data:/data"
        ];

        extraOptions = [
          "--network=opencloud"
        ];

        entrypoint = [ "/bin/sh" ];
        cmd = [
          "-c"
          "opencloud init || true; opencloud server"
        ];
      };
    };
  };

  systemd.services.create-docker-network = with config.virtualisation.oci-containers; {
      serviceConfig.Type = "oneshot";
      wants = [ "${backend}.service" ];
      wantedBy = [ "${backend}-opencloud.service" ];
      script = ''
        ${pkgs.docker}/bin/docker network inspect opencloud >/dev/null 2>&1 || \
        ${pkgs.docker}/bin/docker network create --driver bridge opencloud
      '';
    };

  environment.etc."opencloud/csp.yaml".text = let
      tq = builtins.concatStringsSep "" [ "'" "'" "'" ];
    in ''
    directives:
      child-src:
        - ${tq}self${tq}
      connect-src:
        - ${tq}self${tq}
        - 'blob:'
        - 'https://${opencloud.companionDomain}/'
        - 'wss://${opencloud.companionDomain}/'
        - 'https://raw.githubusercontent.com/opencloud-eu/awesome-apps/'
        - 'https://${opencloud.idpDomain}/'
        - 'https://update.opencloud.eu/'
      default-src:
        - ${tq}none${tq}
      font-src:
        - ${tq}self${tq}
      frame-ancestors:
        - ${tq}self${tq}
      frame-src:
        - ${tq}self${tq}
        - 'blob:'
        - 'https://embed.diagrams.net/'
        # In contrary to bash and docker the default is given after the | character
        - 'https://${opencloud.collaboraDomain}/'
        # This is needed for the external-sites web extension when embedding sites
        - 'https://docs.opencloud.eu'
      img-src:
        - ${tq}self${tq}
        - 'data:'
        - 'blob:'
        - 'https://raw.githubusercontent.com/opencloud-eu/awesome-apps/'
        - 'https://tile.openstreetmap.org/'
        # In contrary to bash and docker the default is given after the | character
        - 'https://${opencloud.collaboraDomain}/'
      manifest-src:
        - ${tq}self${tq}
      media-src:
        - ${tq}self${tq}
      object-src:
        - ${tq}self${tq}
        - 'blob:'
      script-src:
        - ${tq}self${tq}
        - ${tq}unsafe-inline${tq}
        - 'https://${opencloud.idpDomain}/'
      style-src:
        - ${tq}self${tq}
        - ${tq}unsafe-inline${tq}
  '';

  system.stateVersion = "25.11";
}
