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

  systemd.tmpfiles.rules =
    let
      upstreamCaRules =
        lib.flatten (lib.mapAttrsToList (host: v:
          let ca = (v.upstreamTls.trustedCaPem or null);
          in lib.optional (ca != null)
            "f /run/nginx-upstream-cas/${host}.pem 0444 root root - ${ca}"
        ) domains);
    in
    [
      "d /run/secrets 0750 root root - -"
      "d /run/nginx-upstream-cas 0755 root root - -"
      "f /run/secrets/cf_dns_api_token 0400 root root - ${cloudflareDnsApiToken}"
    ] ++ upstreamCaRules;

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

    # Add upstream TLS bits only if upstream is https://
    mkUpstreamTlsConfig = host: v:
      let
        tls = v.upstreamTls or null;
        verify = tls != null && (tls.verify or false);
        hasCa = tls != null && (tls.trustedCaPem or null) != null;

        # If serverName is set, use it for SNI + hostname verification.
        # Otherwise, default to $proxy_host (host from proxy_pass).
        sniName =
          if tls != null && (tls.serverName or null) != null
          then tls.serverName
          else "$proxy_host";

        caPath = "/run/nginx-upstream-cas/${host}.pem";
      in
        lib.optionalString (lib.hasPrefix "https://" v.upstream) ''
          proxy_ssl_server_name on;
          proxy_ssl_name ${sniName};

          ${if verify then ''
            proxy_ssl_verify on;
            ${lib.optionalString hasCa "proxy_ssl_trusted_certificate ${caPath};"}
            # proxy_ssl_verify_depth 2;
          '' else ''
            proxy_ssl_verify off;
          ''}
        '';

    mkLocations = host: v:
      let
        extraLocs =
          lib.mapAttrs
            (_path: loc: {
              proxyPass = v.upstream;
              extraConfig = ''
                ${websocketProxyBits}
                ${mkUpstreamTlsConfig host v}
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
            ${mkUpstreamTlsConfig host v}
          '';
        };
      } // extraLocs);

    # Per-vhost listen list:
    # - if bindIps is omitted: listen on all IPv4+IPv6
    # - if bindIps is set: bind only to those IPs
    mkListen = v:
      let
        ips = v.bindIps or null;

        mk = ip: [
          { addr = ip; port = 80; }
          { addr = ip; port = 443; ssl = true; }
        ];
      in
      if ips == null then [
        { addr = "0.0.0.0"; port = 80; }
        { addr = "0.0.0.0"; port = 443; ssl = true; }
        { addr = "[::]"; port = 80; }
        { addr = "[::]"; port = 443; ssl = true; }
      ] else lib.flatten (map mk ips);
  in
  {
    enable = true;

    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    appendHttpConfig = ''
      map $http_upgrade $connection_upgrade {
        default upgrade;
        "" close;
      }
    '';

    virtualHosts = lib.mapAttrs (host: v: {
      serverName = host;

      enableACME = true;
      forceSSL = true;

      http2 = v.http2 or false;

      # DNS-01: don't set up HTTP-01 webroot
      acmeRoot = null;

      listen = mkListen v;

      locations = mkLocations host v;
      extraConfig = v.extraConfig or "";
    }) domains;
  };

  system.stateVersion = "25.11";
}
