{ config, modulesPath, pkgs, lib, ... }:
let
  postfix = {
    username = "<postfix-username>";
    password = "<postfix-password>";
    gmailAddress = "your.email@gmail.com";
    gmailAppPassword = "<gmail-app-password>";
    interface = "<listening-interface>";
    hostname = "mail.local"; # not important for relaying
    domain = "local"; # not important for relaying
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
    allowedUDPPorts = [ 25 ];
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

    relayHost = "[smtp.gmail.com]:587";
    inetInterfaces = postfix.interface;
    destination = [];

    hostname = postfix.hostname;
    domain   = postfix.domain;

    config = {
      # --- Require SMTP AUTH from clients ---
      smtpd_sasl_auth_enable = "yes";
      smtpd_sasl_type = "cyrus";
      smtpd_sasl_path = "smtpd";
      smtpd_sasl_security_options = "noanonymous";
      broken_sasl_auth_clients = "yes";

      smtpd_recipient_restrictions = "permit_sasl_authenticated,reject";

      # --- Gmail relay auth ---
      smtp_sasl_auth_enable = "yes";
      smtp_sasl_security_options = "noanonymous";
      smtp_sasl_password_maps = "hash:/etc/postfix/sasl_passwd";

      # --- TLS to Gmail ---
      smtp_use_tls = "yes";
      smtp_tls_security_level = "encrypt";
      smtp_tls_CAfile = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      smtp_tls_note_starttls_offer = "yes";

      # No local delivery
      mydestination = "";

      smtp_tls_loglevel = "1";
    };
  };

  environment.etc."postfix/sasl_passwd" = {
    text = ''
      [smtp.gmail.com]:587 ${postfix.gmailAddress}:${postfix.gmailAppPassword}
    '';
    mode = "0600";
  };

  services.cyrus-sasl.enable = true;

  # Create the SASL user automatically
  system.activationScripts.createSaslUser = ''
    echo "${postfix.password}" | \
      ${pkgs.cyrus_sasl}/bin/saslpasswd2 \
        -p -c -u ${postfix.domain} ${postfix.username}
  '';

  # Build postfix maps
  system.activationScripts.postfixMaps = ''
    ${pkgs.postfix}/bin/postmap /etc/postfix/sasl_passwd
  '';

  system.stateVersion = "25.11";
}
