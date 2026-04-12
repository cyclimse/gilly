#!/usr/bin/env bash

set -eu -o pipefail

ARTIFACT="${1:?Usage: gleam_publish.sh <artifact.tar.gz>}"
HEXPM_API_KEY="${HEXPM_API_KEY:-}"

EXTRACT_DIR=$(mktemp -d)
tar -xzf "$ARTIFACT" -C "$EXTRACT_DIR"
cd "$EXTRACT_DIR"

echo "Publishing gilly version $(cat gleam.toml | grep '^version' | awk -F'"' '{print $2}') to Hex.pm"

echo "I am not using semantic versioning" | gleam publish -y
