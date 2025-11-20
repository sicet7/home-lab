{ config, modulesPath, pkgs, lib, ... }: 
let
    mongoRootPassword = "rootPassword"; # Fill out the root password for mongodb (will be set to this)
    mongoPassword = "userPassword"; # Fill out the unifi user password for mongodb (will be set to this)

    # Init Js Script
    mongoInitJs = pkgs.writeText "init-mongo.js" ''
    const env = process.env;
    const authDb   = env.MONGO_AUTHSOURCE || "admin";
    const rootUser = env.MONGO_INITDB_ROOT_USERNAME || "root";
    const rootPass = env.MONGO_INITDB_ROOT_PASSWORD || "";
    const appUser  = env.MONGO_USER || "unifi";
    const appPass  = env.MONGO_PASS || "";
    const baseDb   = env.MONGO_DBNAME || "unifi";

    const admin = db.getSiblingDB(authDb);
    if (!admin.auth(rootUser, rootPass)) {
      throw new Error("Root authentication failed in init script");
    }

    db.getSiblingDB(baseDb);
    db.getSiblingDB(baseDb + "_stat");
    db.getSiblingDB(baseDb + "_audit");

    const ensureUser = (username, pwd, roles) => {
      const existing = admin.getUser(username);
      if (existing) {
        admin.updateUser(username, { pwd: pwd, roles: roles });
        print("Updated user '" + username + "'");
      } else {
        admin.createUser({ user: username, pwd: pwd, roles: roles });
        print("Created user '" + username + "'");
      }
    };

    ensureUser(appUser, appPass, [
      { role: "dbOwner", db: baseDb },
      { role: "dbOwner", db: baseDb + "_stat" },
      { role: "dbOwner", db: baseDb + "_audit" }
    ]);

    print("Mongo init script completed.");
  '';
in
{ 
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];

  nix.settings = { sandbox = false; };

  proxmoxLXC = {
    manageNetwork = false;
    privileged = true;
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

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      80
      443
      8843
      8880
      6789
    ];
    allowedUDPPorts = [
      80
      443
      1900
      3478
      5514
      6789
      8843
      8880
      10001
    ];
  };

  virtualisation.docker.enable = true;

  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      mongo = {
        autoStart = true;
        hostname = "mongo";
        image = "docker.io/mongo:8.2";
        environment = {
          MONGO_INITDB_ROOT_USERNAME = "root";
          MONGO_INITDB_ROOT_PASSWORD = "${mongoRootPassword}";
          MONGO_USER = "unifi";
          MONGO_PASS = "${mongoPassword}";
          MONGO_DBNAME = "unifi";
          MONGO_AUTHSOURCE = "admin";
        };
        volumes = [
          "/docker/mongo/data:/data/db"
          "${mongoInitJs}:/docker-entrypoint-initdb.d/10-init.js:ro"
        ];
        extraOptions = [
          "--network=mdb"
        ];
      };
      unifi-network-application = {
        autoStart = true;
        hostname = "unifi-network-application";
        image = "lscr.io/linuxserver/unifi-network-application:latest";
        dependsOn = [ "mongo" ];
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = "Europe/Copenhagen";
          MONGO_HOST = "mongo";
          MONGO_PORT = "27017";
          MONGO_USER = "unifi";
          MONGO_PASS = "${mongoPassword}";
          MONGO_DBNAME = "unifi";
          MONGO_AUTHSOURCE = "admin";
          MEM_LIMIT = "2048";
          MEM_STARTUP = "2048";
        };
        ports = [
          "443:8443"
          "8443:8443"
          "3478:3478/udp"
          "10001:10001/udp"
          "80:8080"
          "8080:8080"
          "1900:1900/udp"
          "8843:8843"
          "8880:8880"
          "6789:6789"
          "5514:5514/udp"
        ];
        volumes = [
          "/docker/unifi-network-application/data:/config"
        ];
        extraOptions = [
          "--network=mdb"
        ];
      };
    };  
  };

  systemd.services.create-docker-network = with config.virtualisation.oci-containers; {
    serviceConfig.Type = "oneshot";
    wants = [ "${backend}.service" ];
    wantedBy = [ "${backend}-mongo.service" ];
    script = ''
      ${pkgs.docker}/bin/docker network inspect mdb >/dev/null 2>&1 || \
      ${pkgs.docker}/bin/docker network create --driver bridge mdb
    '';
  };

  system.stateVersion = "25.05";
}

