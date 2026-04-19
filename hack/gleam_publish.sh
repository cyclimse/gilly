#!/usr/bin/env bash

set -eu -o pipefail

print_help() {
	echo "Usage: gleam_publish.sh <artifact.tar.gz>"
	echo "Example: gleam_publish.sh gilly-0.3.1.tar.gz"
}

extract_artifact() {
	local artifact="$1"
	local extract_dir
	extract_dir=$(mktemp -d)
	tar -xzf "$artifact" -C "$extract_dir"
	echo "$extract_dir"
}

cleanup() {
	if [[ -n "${EXTRACT_DIR:-}" && -d "$EXTRACT_DIR" ]]; then
		rm -rf "$EXTRACT_DIR"
	fi
}

ARTIFACT="${1:-}"

if [[ -z "$ARTIFACT" ]]; then
	print_help
	exit 1
fi

HEXPM_API_KEY="${HEXPM_API_KEY:-}"

if [[ -z "$HEXPM_API_KEY" ]]; then
	echo "Error: HEXPM_API_KEY environment variable is not set."
	exit 1
fi

EXTRACT_DIR=""
trap cleanup EXIT

EXTRACT_DIR=$(extract_artifact "$ARTIFACT")
cd "$EXTRACT_DIR"

VERSION=$(grep '^version' gleam.toml | awk -F'"' '{print $2}')
echo "Publishing Gilly $VERSION to Hex..."

echo "I am not using semantic versioning" | gleam publish -y

echo "All done!"
