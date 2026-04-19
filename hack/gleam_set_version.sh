#!/usr/bin/env bash

set -eu -o pipefail

PLACEHOLDER_VERSION="0.1.0"

print_help() {
	echo "Usage: gleam_set_version.sh <version>"
	echo "Example: gleam_set_version.sh 0.3.1"
}

replace_placeholder_version() {
	local file="$1"
	local version="$2"
	local verify_pattern="$3"

	if ! grep -q "version = \"$PLACEHOLDER_VERSION\"" "$file"; then
		echo "Error: placeholder version $PLACEHOLDER_VERSION not found in $file"
		exit 1
	fi

	sed -i "s/version = \"$PLACEHOLDER_VERSION\"/version = \"$version\"/g" "$file"

	if ! grep -q "$verify_pattern" "$file"; then
		echo "Error: failed to set version in $file"
		exit 1
	fi
}

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
	print_help
	exit 1
fi

replace_placeholder_version src/gilly/common.gleam "$VERSION" "pub const version = \"$VERSION\""
replace_placeholder_version gleam.toml "$VERSION" "^version = \"$VERSION\""

echo "Set project version to $VERSION"
