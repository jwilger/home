set dotenv-load := false

default:
    @just --list

check:
    nix flake check --print-build-logs

format:
    nix fmt

build profile="jwilger@gregor":
    nix build ".#homeConfigurations.\"{{profile}}\".activationPackage"

capture-noctalia:
    @./scripts/capture-noctalia
