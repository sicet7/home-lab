{ config, modulesPath, pkgs, lib, ... }:
let
  postfix = {
    username = "<local-smtp-username>";
    password = "<local-smtp-password>";
    remoteSmtpHost = "<remote-smtp-host>";
    remoteSmtpPort = "<remote-smtp-port>";
    remoteSmtpUsername = "<remote-smtp-username>";
    remoteSmtpPassword = "<remote-smtp-password>";
    listenInterface = "<ipv4-to-listen-for-local-smtp-clients-on>";
    externalInterface = "<ipv4-to-connect-to-remote-smtp-via>";
    hostname = "mail.local";
    domain = "local";
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
    allowedTCPPorts = [ 25 ];
    allowedUDPPorts = [ ];
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

  services.postfix = {
    enable = true;

    # (Optional) keep this true; it provides the port 25 listener in master.cf
    enableSmtp = true;

    mapFiles.sasl_passwd = pkgs.writeText "sasl_passwd" ''
      [${postfix.remoteSmtpHost}]:${postfix.remoteSmtpPort} ${postfix.remoteSmtpUsername}:${postfix.remoteSmtpPassword}
    '';

    settings.main = {
      # Listen only on a specific interface/IP (or use "loopback-only")
      inet_interfaces = postfix.listenInterface;
      smtp_bind_address = postfix.externalInterface;

      inet_protocols = "ipv4";

      # SMTP relayhost is a LIST in 25.11
      relayhost = [ "[${postfix.remoteSmtpHost}]:${postfix.remoteSmtpPort}" ];

      # Cosmetic identity
      myhostname = postfix.hostname;
      mydomain   = postfix.domain;

      # No local delivery (relay-only)
      mydestination = "";

      # --- Require SMTP AUTH from clients (Cyrus SASL) ---
      smtpd_sasl_auth_enable = "yes";
      smtpd_sasl_type = "cyrus";
      smtpd_sasl_path = "smtpd";
      smtpd_sasl_security_options = "noanonymous";
      broken_sasl_auth_clients = "yes";

      # Realm match (since you create users with -u ${postfix.domain})
      smtpd_sasl_local_domain = postfix.domain;

      # Only authenticated clients may send
      smtpd_client_restrictions = "permit_sasl_authenticated,reject";
      smtpd_recipient_restrictions = "permit_sasl_authenticated,reject";

      # --- mail relay auth (outbound) ---
      smtp_sasl_auth_enable = "yes";
      smtp_sasl_security_options = "noanonymous";
      smtp_sasl_password_maps = "hash:/etc/postfix/sasl_passwd";

      # --- TLS to SMTP server ---
      smtp_use_tls = "yes";
      smtp_tls_security_level = "encrypt";
      smtp_tls_CAfile = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      smtp_tls_note_starttls_offer = "yes";

      smtp_tls_loglevel = "1";
    };
  };

  environment.etc."sasl2/smtpd.conf" = {
    text = ''
      pwcheck_method: auxprop
      auxprop_plugin: sasldb
      mech_list: PLAIN LOGIN
    '';
    mode = "0644";
  };

  environment.systemPackages = [ pkgs.cyrus_sasl ];

  system.activationScripts.createSaslUser = ''
    set -euo pipefail

    echo "${postfix.password}" | \
      ${pkgs.cyrus_sasl}/bin/saslpasswd2 \
        -p -c -u ${postfix.domain} ${postfix.username}

    chown root:postfix /etc/sasldb2 || true
    chmod 0640 /etc/sasldb2 || true
  '';

  system.stateVersion = "25.11";
}
