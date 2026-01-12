{ config, modulesPath, pkgs, lib, ... }:
let
  # ---------------------------
  # User-tunable settings (top)
  # ---------------------------

  # Domain overrides -> local IP(s)
  # value can be a string (single IP) or a list of strings (multiple IPs)
  overrides = {
    "home.arpa" = "192.168.1.1";
    "nas.home.arpa" = "192.168.1.10";
    # "printer.lan" = [ "192.168.1.20" "192.168.1.21" ];
  };

  # DNS-over-TLS upstreams (easy to add more)
  # Each: { addr = "IP"; port = 853; authName = "SNI/hostname"; }
  dotUpstreams = [
    { addr = "1.1.1.1"; port = 853; authName = "cloudflare-dns.com"; }
    { addr = "1.0.0.1"; port = 853; authName = "cloudflare-dns.com"; }

    { addr = "9.9.9.9"; port = 853; authName = "dns.quad9.net"; }
    { addr = "149.112.112.112"; port = 853; authName = "dns.quad9.net"; }

    { addr = "8.8.8.8"; port = 853; authName = "dns.google"; }
    { addr = "8.8.4.4"; port = 853; authName = "dns.google"; }
  ];
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
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };

  security.pam.services.sshd.allowNullPassword = lib.mkForce false;
  services.fstrim.enable = false;
  services.openssh = {
    enable = false;
    openFirewall = false;
  };

  environment.etc."ssl/certs/ca-certificates.crt".source = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  services.resolved.enable = lib.mkDefault false;

  services.unbound = {
    enable = true;

    settings = {
      server = {
        interface = [ "0.0.0.0" "::0" ];
        port = 53;

        # Allow common private ranges + localhost (tighten if you want)
        access-control = [
          "127.0.0.0/8 allow"
          "::1 allow"
          "10.0.0.0/8 allow"
          "172.16.0.0/12 allow"
          "192.168.0.0/16 allow"
        ];

        do-ip4 = "yes";
        do-ip6 = "yes";
        do-udp = "yes";
        do-tcp = "yes";

        prefetch = "yes";
        hide-identity = "yes";
        hide-version = "yes";
        qname-minimisation = "yes";

        harden-glue = "yes";
        harden-dnssec-stripped = "yes";
        deny-any = "yes";

        # DNSSEC validation
        trust-anchor-file = "${pkgs.unbound}/etc/unbound/root.key";
        val-permissive-mode = "no";
      };

      forward-zone = [
        {
          name = ".";
          forward-tls-upstream = "yes";
          forward-addr =
            map (u: "${u.addr}@${toString u.port}#${u.authName}") dotUpstreams;
        }
      ];
    };

    extraConfig =
      let
        mkA = domain: ip: ''local-data: "${domain}. IN A ${ip}"'';
        mkAAAA = domain: ip: ''local-data: "${domain}. IN AAAA ${ip}"'';
        isV6 = s: lib.hasInfix ":" s;

        domainToLines = domain: value:
          let
            ips = if builtins.isList value then value else [ value ];
            zoneLine = ''local-zone: "${domain}." transparent'';
            dataLines =
              map (ip: if isV6 ip then mkAAAA domain ip else mkA domain ip) ips;
          in
            [ zoneLine ] ++ dataLines;

        overrideLines =
          lib.concatStringsSep "\n"
            (lib.concatLists (lib.mapAttrsToList domainToLines overrides));
      in
      ''
        # --- Local overrides (generated) ---
        ${overrideLines}
      '';
  };

  system.stateVersion = "25.11";
}
