#!/usr/bin/env bash

set -eu -o pipefail

ARTIFACT="${1:?Usage: gleam_publish.sh <artifact.tar.gz>}"
HEXPM_API_KEY="${HEXPM_API_KEY:-}"

DIR=$(basename "$ARTIFACT" .tar.gz)
tar -xzf "$ARTIFACT"
cd "$DIR"

echo "Publishing gilly version $(cat gleam.toml | grep '^version' | awk -F'"' '{print $2}') to Hex.pm"

echo "I am not using semantic versioning" | gleam publish -y
