{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = { ... }@inputs:
    let
      forEachShellSystem = f: lib.genAttrs shellSystems (system: f system);
      forEachSupportedSystem = f: lib.genAttrs supportedSystems (system: f system);
      imageName = "minecraft-vanilla";
      imageTag = "1.21.3";
      lib = inputs.nixpkgs.lib;

      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      shellSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      mkDockerImage =
        pkgs: targetSystem:
        let
          archSuffix = if targetSystem == "x86_64-linux" then "amd64" else "arm64";

          minecraft_server_jar = builtins.fetchurl {
            url = "https://piston-data.mojang.com/v1/objects/45810d238246d90e811d896f87b14695b7fb6839/server.jar";
            sha256 = "sha256:1ddgz0dh830869v82q0cp3zkyanl1p45f7ccbvgrr0y00advhlz1";
          };

          minecraft_start_script = { pkgs }:
            pkgs.writeShellScriptBin "minecraft_start_script" ''
              function sigterm_handler() {
                echo "SIGTERM handler triggered"
                ${pkgs.rconc}/bin/rconc 127.0.0.1:25575 "stop"
                echo "Waiting for minecraft to stop..."
                while ${pkgs.procps}/bin/kill -0 $(${pkgs.coreutils}/bin/cat /tmp/minecraft.pid) &>/dev/null; do
                  ${pkgs.coreutils}/bin/sleep 0.1
                done
                echo "Minecraft stopped"
              }
              trap sigterm_handler SIGTERM

              ${pkgs.coreutils}/bin/cp ${minecraft_server_properties {inherit pkgs;}} /srv/minecraft/server.properties
              ${pkgs.coreutils}/bin/cp ${minecraft_eula_txt {inherit pkgs;}} /srv/minecraft/eula.txt
              cd /srv/minecraft

              ${pkgs.corretto21}/bin/java \
                $JAVA_ARGS \
                -jar ${minecraft_server_jar} &

              echo "$!" > /tmp/minecraft.pid

              while ${pkgs.procps}/bin/kill -0 $(${pkgs.coreutils}/bin/cat /tmp/minecraft.pid) &>/dev/null; do
                ${pkgs.coreutils}/bin/sleep 60
                ${pkgs.rconc}/bin/rconc 127.0.0.1:25575 "save-all flush"
              done
            '';

          minecraft_server_properties = { pkgs }:
            pkgs.writeText "server.properties" ''
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
              enable-rcon=true
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

          minecraft_eula_txt = { pkgs }:
            pkgs.writeText "eula.txt" ''
              eula=true
            '';

          container_packages = { pkgs }: with pkgs; [
            (minecraft_start_script { inherit pkgs; })
            coreutils
            dockerTools.binSh
            dockerTools.caCertificates
            rconc
          ];
        in
        pkgs.dockerTools.buildLayeredImage {
          name = imageName;
          tag = "${imageTag}-${archSuffix}";
          contents = pkgs.buildEnv {
            name = "image-root";
            paths = container_packages { inherit pkgs; };
            pathsToLink = [ "/bin" "/etc" "/var" ];
          };
          fakeRootCommands = ''
            mkdir /tmp
            chmod 1777 /tmp
          '';
        };
    in
    {
      packages = forEachSupportedSystem (
        system:
        let
          crossPkgs = (if inputs.nixpkgs.stdenv.isx86_64 then (import inputs.nixpkgs { localSystem = "aarch64-linux"; }) else (import inputs.nixpkgs { localSystem = "x86_64-linux"; }));
          pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [
              (self: super: {
                inherit (crossPkgs)
                  coreutils
                  corretto21
                  procps
                  rconc
                  ;
              })
            ];
          };

          buildForLinux =
            targetSystem:
            if system == targetSystem then
              mkDockerImage pkgs targetSystem
            else
              mkDockerImage
                (import inputs.nixpkgs {
                  localSystem = system;
                  crossSystem = targetSystem;
                  overlays = [
                    (self: super: {
                      inherit (crossPkgs);
                    })
                  ];
                })
                targetSystem;
        in
        {
          "amd64" = buildForLinux "x86_64-linux";
          "arm64" = buildForLinux "aarch64-linux";
        }
      );

      devShells = forEachShellSystem (system:
        (
          let
            pkgs = import inputs.nixpkgs {
              inherit system;
            };
          in
          {
            "default" = pkgs.mkShellNoCC {
              packages = [
                pkgs.just
                pkgs.nix-fast-build
              ];
            };
          }
        ));

      apps = forEachSupportedSystem (system: {
        default = {
          type = "app";
          program = toString (
            inputs.nixpkgs.legacyPackages.${system}.writeScript "build-multi-arch" ''
              #!${inputs.nixpkgs.legacyPackages.${system}.bash}/bin/bash
              set -e
              echo "Building x86_64-linux image..."
              nix build .#amd64 --out-link result-${system}-amd64
              echo "Building aarch64-linux image..."
              nix build .#arm64 --out-link result-${system}-arm64
            ''
          );
        };
      });
    };
}
