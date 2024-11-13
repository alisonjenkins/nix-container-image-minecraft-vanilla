# Build the container with Nix
build tag:
    #!/usr/bin/env bash
    set -euo pipefail

    case $(uname -m) in
        arm64)
        ARCH=aarch64
        ;;
        x86_64)
        ARCH=x86_64
        ;;
    esac
    nix build -o container_aarch64 ".#packages.$ARCH-linux.container_aarch64" && \
        podman load < container_aarch64
    nix build -o container_x86_64 ".#packages.$ARCH-linux.container_x86_64" && \
        podman load < container_x86_64

    aws ecr get-login-password --profile alisonRW-script --region eu-west-1 | podman login --username AWS --password-stdin 918821718107.dkr.ecr.eu-west-1.amazonaws.com

    REPO="918821718107.dkr.ecr.eu-west-1.amazonaws.com/minecraft"
    TAG="{{tag}}"
    podman manifest create --amend "$REPO:$TAG"
    podman manifest add "$REPO:$TAG" "localhost/minecraft:latest-aarch64" &
    podman manifest add "$REPO:$TAG" "localhost/minecraft:latest-x86_64" &
    wait
    podman manifest push --all --rm "$REPO:$TAG"

# Inspect the container
dive:
    dive podman://localhost/minecraft:latest-x86_64

# Run the container
run:
    podman run -it --rm -v $(pwd)/world:/srv/minecraft/world -v $(pwd)/tmp:/tmp -p 25565:25565 localhost/minecraft:latest-x86_64

alias b := build
alias d := dive
alias r := run
