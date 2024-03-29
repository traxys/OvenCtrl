{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.services.oven-media-engine;

  valueType = with lib.types;
    types.nullOr (oneOf [
      int
      float
      bool
      str
      path
      (attrsOf valueType)
    ])
    // {description = "OME XML Value";};

  toXml = v: let
    toXmlAttrs = v:
      lib.concatStrings (lib.mapAttrsToList (compoundName: value: let
        name = builtins.elemAt (lib.splitString "#" compoundName) 0;
      in
        if builtins.isAttrs value && builtins.hasAttr "__value" value
        then
          if builtins.attrNames value != ["__attrs" "__value"]
          then throw "Special attrs must be of the form {__value = ...; __attrs = {...};}"
          else let
            attrs =
              lib.concatStringsSep " "
              (lib.mapAttrsToList (name: value: "${name}=\"${lib.escapeXML value}\"") value.__attrs);
          in
            if value.__value == null
            then "<${name} ${attrs} />"
            else "<${name} ${attrs}>${toXml value.__value}</${name}>"
        else "<${name}>${toXml value}</${name}>")
      v);
  in
    if builtins.isString v
    then lib.strings.escapeXML v
    else if (builtins.isFloat v) || (builtins.isInt v) || (builtins.isPath v)
    then toString v
    else if builtins.isAttrs v
    then toXmlAttrs v
    else if builtins.isBool v
    then
      if v
      then "true"
      else "false"
    else throw "Unhandled value: ${toString v}";
in {
  options.services.oven-media-engine = {
    enable = mkEnableOption "oven-media-engine, a Sub-Second Latency Streaming Server";

    package = mkOption {
      type = types.package;
      description = "Package to use OvenMediaEngine";
      default = pkgs.oven-media-engine;
    };

    serverSettings = mkOption {
      type = valueType;
      description = "Server.xml configuration (content of the Server block, version 8)";
    };

    loggerSettings = mkOption {
      type = valueType;
      description = "Logger.xml configuration (content of the Logger Block, version 2)";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.oven-media-engine = {
      description = "OvenMediaEngine";
      after = ["network.target" "postgresql.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = let
        serverXml = pkgs.writeText "Server.xml" ''
          <?xml version="1.0" encoding="UTF-8"?>
          <Server version="8">
            ${toXml cfg.serverSettings}
          </Server>
        '';
        loggerXml = pkgs.writeText "Logger.xml" ''
          <?xml version="1.0" encoding="UTF-8"?>
          <Logger version="2">
            ${toXml cfg.loggerSettings}
          </Logger>
        '';
        configDir = pkgs.runCommand "OME-Config" {} ''
          mkdir $out
          cat ${loggerXml} > $out/Logger.xml
          ${pkgs.libxml2.bin}/bin/xmllint --format $out/Logger.xml --output $out/Logger.xml
          cat ${serverXml} > $out/Server.xml
          ${pkgs.libxml2.bin}/bin/xmllint --format $out/Server.xml --output $out/Server.xml
        '';
      in {
        Type = "simple";
        User = "ome";
        DynamicUser = true;
        ExecStart = "${cfg.package}/bin/OvenMediaEngine -c ${configDir}";
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
