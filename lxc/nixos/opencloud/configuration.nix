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
    idpDomain = "<idp-domain>";
    idpClientId = "<idp-client-id>";
    collaboraDomain = "<collabora-domain>";
    companionDomain = "<companion-domain>";
    wopiserverDomain = "<wopiserver-domain>";
  };
  collabora = {
    username = "<collabora-admin-username>";
    password = "<collabora-admin-password>";
  };
in
{ 
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];

  nixpkgs.config.allowUnfree = true;

  fonts = {
    fontconfig.enable = true;

    fontDir.enable = true;

    packages = with pkgs; [
      corefonts
      liberation_ttf
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
    ];
  };

  nix.settings = { sandbox = false; };

  proxmoxLXC = {
    manageNetwork = false;
    privileged = true;
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 9200 9980 ];
    allowedUDPPorts = [ 9200 9980 ];
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

  systemd.tmpfiles.rules = [
    "d ${nfs.localMountpoint}/config 0750 1000 1000 -"
    "d ${nfs.localMountpoint}/data   0750 1000 1000 -"
    "d /var/lib/opencloud/nats       0750 1000 1000 -"
  ];

  systemd.services.docker.after = [ "remote-fs.target" ];
  systemd.services.docker.wants = [ "remote-fs.target" ];

  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      opencloud = {
        autoStart = true;
        hostname = "opencloud";
        image = "docker.io/opencloudeu/opencloud-rolling:4.1";

        environment = {
          # --- Base ---
          OC_URL = "https://${opencloud.domain}";
          PROXY_HTTP_ADDR = "0.0.0.0:9200";
          PROXY_TLS = "false";
          OC_INSECURE = "true"; # behind TLS-terminating reverse proxy
          OC_CONFIG_DIR = "/etc/opencloud";
          OC_DATA_DIR = "/var/lib/opencloud";

          # --- Disable builtin IdP; use Keycloak ---
          OC_EXCLUDE_RUN_SERVICES = "idp";
          OC_OIDC_ISSUER = opencloud.oidcIssuer;
          OC_OIDC_CLIENT_ID = opencloud.idpClientId;

          # --- OIDC proxy behavior ---
          PROXY_OIDC_REWRITE_WELLKNOWN = "true";
          PROXY_INSECURE_BACKENDS = "true";
          PROXY_ENABLE_BASIC_AUTH = "false";
          PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD = "jwt";
          PROXY_OIDC_SKIP_USER_INFO = "true";

          # --- Autoprovision users from claims ---
          PROXY_AUTOPROVISION_ACCOUNTS = "true";
          GRAPH_USERNAME_MATCH = "none";
          PROXY_AUTOPROVISION_CLAIM_USERNAME = "opencloud_username";
          PROXY_AUTOPROVISION_CLAIM_EMAIL = "email";
          PROXY_AUTOPROVISION_CLAIM_DISPLAYNAME = "name";

          NATS_NATS_HOST = "0.0.0.0";
          NATS_NATS_STORE_DIR = "/var/lib/nats";
          GATEWAY_GRPC_ADDR = "0.0.0.0:9142";

          # --- User identity mapping ---
          PROXY_USER_OIDC_CLAIM = "sub";
          PROXY_USER_CS3_CLAIM = "userid";

          # --- Role assignment from OIDC ---
          PROXY_ROLE_ASSIGNMENT_DRIVER = "oidc";
          PROXY_ROLE_ASSIGNMENT_OIDC_CLAIM = "opencloud_role";
          GRAPH_ASSIGN_DEFAULT_USER_ROLE = "false";

          # --- CSP + misc ---
          PROXY_CSP_CONFIG_FILE_LOCATION = "/etc/opencloud/csp.yaml";

          STORAGE_USERS_DATA_GATEWAY_URL = "http://opencloud:9200/data";

          # --- Logging ---
          OC_LOG_COLOR = "false";
          OC_LOG_LEVEL = "warn";
          OC_LOG_PRETTY = "false";

          # --- Collabora integration bits (from your compose) ---
          COLLABORA_DOMAIN = opencloud.collaboraDomain;
          FRONTEND_APP_HANDLER_SECURE_VIEW_APP_ADDR = "eu.opencloud.api.collaboration";
        };
        ports = [
           "9200:9200"
        ];
        volumes = [
          "/etc/opencloud/csp.yaml:/etc/opencloud/csp.yaml:ro"
          "/var/lib/opencloud/nats:/var/lib/nats"
          "${nfs.localMountpoint}/data:/var/lib/opencloud"
          "${nfs.localMountpoint}/config:/etc/opencloud"
        ];

        extraOptions = [
          "--network=opencloud"
          "--user=1000:1000"
        ];

        entrypoint = "/bin/sh";
        cmd = [
          "-c"
          "opencloud init || true; opencloud server"
        ];
      };

      collabora = {
        autoStart = true;
        hostname = "collabora";
        image = "docker.io/collabora/code:25.04.7.1.1";

        entrypoint = "/bin/bash";

        cmd = [
          "-c"
          "coolconfig generate-proof-key && /start-collabora-online.sh"
        ];

        environment = {
          DONT_GEN_SSL_CERT = "YES";

          aliasgroup1 = "https://${opencloud.wopiserverDomain}";

          extra_params = ''
            --o:ssl.enable=false \
            --o:ssl.ssl_verification=false \
            --o:ssl.termination=true \
            --o:welcome.enable=false \
            --o:net.frame_ancestors=${opencloud.domain} \
            --o:net.lok_allow.host[14]=${opencloud.domain} \
            --o:home_mode.enable=false
          '';

          username = collabora.username;
          password = collabora.password;
        };

        ports = [
          "9980:9980"
        ];

        volumes = [
          "/run/current-system/sw/share/X11/fonts:/usr/share/fonts:ro"
          "/run/current-system/sw/share/X11/fonts:/opt/cool/systemplate/usr/share/fonts:ro"
        ];

        extraOptions = [
          "--cap-add=MKNOD"
          "--network=opencloud"
          "--cap-add=SYS_ADMIN"
          "--security-opt=apparmor=unconfined"

          "--health-cmd=curl -f http://localhost:9980/hosting/discovery || exit 1"
          "--health-interval=15s"
          "--health-timeout=10s"
          "--health-retries=5"
        ];
      };

      collaboration = {
        autoStart = true;
        image = "docker.io/opencloudeu/opencloud-rolling:4.1";

        entrypoint = "/bin/sh";
        cmd = [ "-c" "opencloud collaboration server" ];

        # Start after the others (order only, not health)
        dependsOn = [ "opencloud" "collabora" ];

        environment = {
          COLLABORATION_APP_ADDR = "https://${opencloud.collaboraDomain}";
          COLLABORATION_APP_ICON = "https://${opencloud.collaboraDomain}/favicon.ico";
          COLLABORATION_APP_INSECURE = "true";
          COLLABORATION_APP_NAME = "CollaboraOnline";
          COLLABORATION_APP_PRODUCT = "Collabora";

          COLLABORATION_GRPC_ADDR = "0.0.0.0:9301";
          COLLABORATION_HTTP_ADDR = "0.0.0.0:9300";
          COLLABORATION_LOG_LEVEL = "info";

          COLLABORATION_WOPI_SRC = "https://${opencloud.wopiserverDomain}";

          MICRO_REGISTRY = "nats-js-kv";
          MICRO_REGISTRY_ADDRESS = "opencloud:9233";

          OC_URL = "https://${opencloud.domain}";
        };

        extraOptions = [
          "--user=1000:1000"
          "--network=opencloud"
        ];

        volumes = [
          "${nfs.localMountpoint}/config:/etc/opencloud"
        ];

        # Optional: only if you want local debug access
        # ports = [ "127.0.0.1:9300:9300" ];
      };
    };
  };

  systemd.services.create-opencloud-net = with config.virtualisation.oci-containers; {
    serviceConfig.Type = "oneshot";
    wants = [ "${backend}.service" ];
    after = [ "${backend}.service" ];
    wantedBy = [
      "${backend}-opencloud.service"
      "${backend}-collabora.service"
      "${backend}-collaboration.service"
    ];
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
