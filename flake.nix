{
  description = "An Minecraft container image created using Nix";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = {self, ...} @ inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import inputs.nixpkgs {
        inherit system;
      };

      pkgs_arm64 = import inputs.nixpkgs {
        system = "aarch64-linux";
      };

      minecraft_server_jar = builtins.fetchurl {
        url = "https://piston-data.mojang.com/v1/objects/59353fb40c36d304f2035d51e7d6e6baa98dc05c/server.jar";
        sha256 = "sha256:1fxl66938ixks6imz8c5bry69z0kh6iawq1fiwca1kck7rlmbg73";
      };

      minecraft_start_script_x86_64 = pkgs.writeShellScriptBin "minecraft_start_script" ''
        ${pkgs.coreutils}/bin/cp ${minecraft_server_properties} /srv/minecraft/server.properties
        ${pkgs.coreutils}/bin/cp ${minecraft_eula_txt} /srv/minecraft/eula.txt
        cd /srv/minecraft
        ${pkgs.corretto21}/bin/java \
          -XX:+AlwaysPreTouch \
          -XX:-DisableExplicitGC \
          -XX:+UseNUMA \
          -XX:+UseTransparentHugePages \
          -XX:+UseShenandoahGC \
          -XX:+ClassUnloadingWithConcurrentMark \
          -Dsun.net.client.defaultConnectTimeout=1000 \
          -Dfml.ignoreInvalidMinecraftCertificates=true \
          -Dfml.ignorePatchDiscrepancies=true \
          -jar ${minecraft_server_jar}
      '';

      minecraft_start_script_arm64 = pkgs.writeShellScriptBin "minecraft_start_script" ''
        ${pkgs_arm64.coreutils}/bin/cp ${minecraft_server_properties} /srv/minecraft/server.properties
        ${pkgs_arm64.coreutils}/bin/cp ${minecraft_eula_txt} /srv/minecraft/eula.txt
        cd /srv/minecraft
        ${pkgs_arm64.corretto21}/bin/java \
          -XX:+AlwaysPreTouch \
          -XX:-DisableExplicitGC \
          -XX:+UseNUMA \
          -XX:+UseTransparentHugePages \
          -XX:+UseShenandoahGC \
          -XX:+ClassUnloadingWithConcurrentMark \
          -Dsun.net.client.defaultConnectTimeout=1000 \
          -Dfml.ignoreInvalidMinecraftCertificates=true \
          -Dfml.ignorePatchDiscrepancies=true \
          -jar ${minecraft_server_jar}
      '';

      minecraft_server_properties = pkgs.writeText "server.properties" ''
        accepts-transfers=false
        allow-flight=false
        allow-nether=true
        broadcast-console-to-ops=true
        broadcast-rcon-to-ops=true
        bug-report-link=
        difficulty=easy
        enable-command-block=false
        enable-jmx-monitoring=false
        enable-query=false
        enable-rcon=false
        enable-status=true
        enforce-secure-profile=true
        enforce-whitelist=false
        entity-broadcast-range-percentage=100
        force-gamemode=false
        function-permission-level=2
        gamemode=survival
        generate-structures=true
        generator-settings={}
        hardcore=false
        hide-online-players=false
        initial-disabled-packs=
        initial-enabled-packs=vanilla
        level-name=world
        level-seed=
        level-type=minecraft\:normal
        log-ips=true
        max-chained-neighbor-updates=1000000
        max-players=20
        max-tick-time=60000
        max-world-size=29999984
        motd=Alison's Vanilla Minecraft v1.20.1
        network-compression-threshold=256
        online-mode=true
        op-permission-level=4
        player-idle-timeout=0
        prevent-proxy-connections=false
        pvp=true
        query.port=25565
        rate-limit=0
        rcon.password=
        rcon.port=25575
        region-file-compression=deflate
        require-resource-pack=false
        resource-pack=https\://minecraft.redwood-guild.com/resource-packs/purebdcraft/64x/64x-MC121.zip
        resource-pack-id=
        resource-pack-prompt=
        resource-pack-sha1=a207d031273ea7e36b5d3db588667b9a8b57d5cf
        server-ip=
        server-port=25565
        simulation-distance=10
        spawn-animals=true
        spawn-monsters=true
        spawn-npcs=true
        spawn-protection=16
        sync-chunk-writes=true
        text-filtering-config=
        use-native-transport=true
        view-distance=10
        white-list=false
      '';

      minecraft_eula_txt = pkgs.writeText "eula.txt" ''
        eula=true
      '';

      container_aarch64 = pkgs.pkgsCross.aarch64-multiplatform.dockerTools.buildLayeredImage {
        name = "minecraft";
        tag = "latest-aarch64";
        config.Cmd = ["/bin/minecraft_start_script"];
        contents = pkgs.pkgsCross.aarch64-multiplatform.buildEnv {
          name = "image-root";
          paths = with pkgs.pkgsCross.aarch64-multiplatform; [
            dockerTools.caCertificates
            minecraft_start_script_arm64
          ];
          pathsToLink = ["/bin" "/etc" "/var"];
        };
        fakeRootCommands = ''
          mkdir /tmp
          chmod 1777 /tmp
        '';
      };

      container_x86_64 = pkgs.dockerTools.buildLayeredImage {
        name = "minecraft";
        tag = "latest-x86_64";
        config.Cmd = ["/bin/minecraft_start_script"];
        contents = pkgs.buildEnv {
          name = "image-root";
          paths = with pkgs; [
            dockerTools.caCertificates
            minecraft_start_script_x86_64
          ];
          pathsToLink = ["/bin" "/etc" "/var"];
        };
        fakeRootCommands = ''
          mkdir /tmp
          chmod 1777 /tmp
        '';
      };
    in {
      packages = {
        container_x86_64 = container_x86_64;
        container_aarch64 = container_aarch64;
      };

      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.just
          pkgs.podman
        ];
      };
    });
}
