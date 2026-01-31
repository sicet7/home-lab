{ config, modulesPath, pkgs, lib, ... }:
let
  # true  => Let's Encrypt staging
  # false => Let's Encrypt production
  acmeUseStaging = true;
  acmeEmail = "you@example.com";
  cloudflareDnsApiToken = "PASTE_TOKEN_HERE";

  domains = {
    "example.com" = {
      upstream = "http://10.0.0.20:8080";
      extraConfig = ''
        client_max_body_size 2g;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        send_timeout 3600s;
      '';
      locations = {
        "/socket/" = {
          extraConfig = ''
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
          '';
        };
      };
    };
  };
in
{
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];

  nix.settings = { sandbox = false; };

  proxmoxLXC = {
    manageNetwork = false;
    privileged = true;
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 ];
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

  systemd.tmpfiles.rules = [
    "f /run/secrets/cf_dns_api_token 0400 root root - ${cloudflareDnsApiToken}"
  ];

  security.acme = let
    acmeServer =
        if acmeUseStaging
        then "https://acme-staging-v02.api.letsencrypt.org/directory"
        else "https://acme-v02.api.letsencrypt.org/directory";
  in {
    acceptTerms = true;

    defaults = {
      email = acmeEmail;
      server = acmeServer;
      dnsProvider = "cloudflare";

      # lego supports *_FILE vars; NixOS wires these via systemd credentials
      credentialFiles = {
        "CF_DNS_API_TOKEN_FILE" = "/run/secrets/cf_dns_api_token";
      };
    };

    # One cert per hostname in domains
    certs = lib.mapAttrs (_host: _v: { }) domains;
  };

  services.nginx = let
    websocketProxyBits = ''
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;

      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;

      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
    '';

    mkLocations = v:
      let
        extraLocs =
          lib.mapAttrs
            (_path: loc: {
              proxyPass = v.upstream;
              extraConfig = ''
                ${websocketProxyBits}
                ${loc.extraConfig or ""}
              '';
            })
            (v.locations or {});
      in
      ({
        "/" = {
          proxyPass = v.upstream;
          extraConfig = ''
            ${websocketProxyBits}
          '';
        };
      } // extraLocs);
  in {
    enable = true;

    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    appendHttpConfig = ''
      map $http_upgrade $connection_upgrade {
        default upgrade;
        ""      close;
      }
    '';

    virtualHosts = lib.mapAttrs (host: v: {
      serverName = host;

      enableACME = true;
      forceSSL = true;

      # DNS-01: don't set up HTTP-01 webroot
      acmeRoot = null;

      locations = mkLocations v;
      extraConfig = v.extraConfig or "";
    }) domains;
  };

  system.stateVersion = "25.11";
}
