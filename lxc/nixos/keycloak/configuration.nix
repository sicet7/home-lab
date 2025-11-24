{ config, modulesPath, pkgs, lib, ... }:
let
  kc = {
    initialAdminPassword = "<kc-admin-password>";
    hostname = "<kc-hostname>";
  };
  db = {
    host = "<db-host>";
    port = 5432;
    username = "<db-username>";
    password = "<db-password>";
    name = "<db-nmame>";
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
    allowedTCPPorts = [ 443 9000 ];
    allowedUDPPorts = [ 443 9000 ];
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

  environment.systemPackages = [
    pkgs.openssl
  ];

  services.keycloak = {
    enable = true;
    package = pkgs.keycloak;
    initialAdminPassword = "${kc.initialAdminPassword}";
    sslCertificate = "/var/lib/kc_cert/server.crt";
    sslCertificateKey = "/var/lib/kc_cert/server.key";

    database = {
      createLocally = false;
      type = "postgresql";
      host = "${db.host}";
      username = "${db.username}";
      port = db.port;
      name = "${db.name}";
      useSSL = false;
      passwordFile = "/var/lib/.keycloak-pgpass";
    };

    settings = {
      http-enabled = false;
      https-port = 443;
      hostname = "${kc.hostname}";
      proxy-protocol-enabled = true;
      http-management-port = 9000;
      http-management-scheme = "inherited";
      https-protocols = "TLSv1.3";
    };

  };

  system.activationScripts.writePgPass.text = ''
    echo "${db.password}" > /var/lib/.keycloak-pgpass
    chown root:root /var/lib/.keycloak-pgpass
    chmod 600 /var/lib/.keycloak-pgpass
  '';

  system.activationScripts.generateCert = {
    text = ''
      CERT_DIR="/var/lib/kc_cert"
      mkdir -p "$CERT_DIR"
      chmod 700 "$CERT_DIR"

      KEY_FILE="$CERT_DIR/server.key"
      CRT_FILE="$CERT_DIR/server.crt"

      if [ ! -f "$KEY_FILE" ]; then
        echo "Generating new TLS key..."
        ${pkgs.openssl}/bin/openssl genrsa -out "$KEY_FILE" 4096
        chmod 600 "$KEY_FILE"
      fi

      if [ ! -f "$CRT_FILE" ]; then
        echo "Generating new self-signed certificate..."
        ${pkgs.openssl}/bin/openssl req -new -x509 \
          -key "$KEY_FILE" \
          -out "$CRT_FILE" \
          -days 3650 \
          -subj "/CN=${kc.hostname}"
        chmod 644 "$CRT_FILE"
      fi
    '';
  };

  system.stateVersion = "25.05";
}
