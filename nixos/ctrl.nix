self: {
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.services.oven-ctrl;

  format = pkgs.formats.toml {};

  configFile = format.generate "oven-ctrl.toml" cfg.settings;
in {
  options.services.oven-ctrl = {
    enable = mkEnableOption "oven-ctrl, a controller for oven-media-engine";

    package = mkOption {
      type = types.package;
      "default" = self.packages.${pkgs.system}.default;
    };

    environmentFile = mkOption {
      type = with types; nullOr (either path (listOf path));
      description = "Environment file (or files) to pass to oven-ctrl. Useful for passwords.";
      default = null;
    };

    settings = mkOption {
      type = types.submodule {
        freeformType = format.type;
        options = {
          external_host = mkOption {
            type = types.str;
            description = "Address of the oven-media-engine";
          };

          port = mkOption {
            type = types.port;
            description = "Port on which oven-ctrl listens";
            default = 3000;
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.oven-ctrl = {
      description = "oven-ctrl";
      after = ["network.target" "postgresql.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = "ome";
        DynamicUser = true;
        ExecStart = "${lib.getExe cfg.package} ${configFile}";
        EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
        # Security
        NoNewPrivileges = true;
        # Sandboxing
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateUsers = true;
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = ["AF_UNIX AF_INET AF_INET6"];
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        PrivateMounts = true;
      };
    };
  };
}
