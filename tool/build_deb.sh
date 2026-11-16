#!/usr/bin/env bash
# Build the SDS-Remote Debian package together with its SHA-256 checksum.
#
# flutter_to_debian 2.0.2 does not read `Depends` from debian/debian.yaml,
# writes a minimal control file, omits the bin launcher symlink and installs
# the launcher icon into a non-standard directory. This script wraps the
# build and repairs those fields before repacking the package.
#
# Steps:
#   1. flutter build linux --release
#   2. flutter_to_debian (creates build/linux/<arch>/release/debian/*.deb)
#   3. Unpack, write a complete control file, add the launcher symlink and
#      install the icon into the hicolor icon theme
#   4. Repack as root:root into dist/
#   5. Write and verify dist/<package>_<version>_<arch>.deb.sha256
#
# Usage: tool/build_deb.sh
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

config="debian/debian.yaml"
homepage="https://github.com/klumw/sdsremote"
section="utils"
icon_theme_dir="usr/share/icons/hicolor/256x256/apps"

# Read a scalar value below a top-level section of debian.yaml.
yaml_value() {
  local section_name="$1"
  local key="$2"
  awk -v want_section="$section_name" -v want_key="$key" '
    /^[^[:space:]#]/ { in_section = index($0, want_section ":") == 1; next }
    in_section && $0 ~ ("^[[:space:]]+" want_key ":") {
      value = $0
      sub("^[[:space:]]+" want_key ":[[:space:]]*", "", value)
      print value
      exit
    }
  ' "$config"
}

for cmd in flutter flutter_to_debian dpkg-deb sha256sum du mktemp awk; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command not found: $cmd" >&2
    exit 1
  fi
done

if [ ! -f "$config" ]; then
  echo "error: $config not found" >&2
  exit 1
fi

package="$(yaml_value control Package)"
version="$(yaml_value control Version)"
arch="$(yaml_value control Architecture)"
maintainer="$(yaml_value control Maintainer)"
priority="$(yaml_value control Priority)"
description="$(yaml_value control Description)"
depends="$(yaml_value control Depends)"
command_name="$(yaml_value flutter_app command)"
parent_dir="$(yaml_value flutter_app parent)"
flutter_arch="$(yaml_value flutter_app arch)"
exec_out_dir="$(yaml_value options exec_out_dir)"

parent_dir="${parent_dir%/}"
parent_dir="${parent_dir:-/opt}"
flutter_arch="${flutter_arch:-x64}"
exec_out_dir="${exec_out_dir:-build/linux/$flutter_arch/release/debian}"

for required in package version arch maintainer description command_name; do
  if [ -z "${!required}" ]; then
    echo "error: '$required' is missing in $config" >&2
    exit 1
  fi
done

deb_name="${package}_${version}_${arch}.deb"

echo "==> Building Linux release bundle"
flutter build linux --release

echo "==> Creating Debian package with flutter_to_debian"
flutter_to_debian

built_deb="$exec_out_dir/$deb_name"
if [ ! -f "$built_deb" ]; then
  echo "error: expected Debian package not found: $built_deb" >&2
  exit 1
fi

echo "==> Repairing package metadata and layout"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
dpkg-deb -R "$built_deb" "$work_dir"

installed_size="$(du -sk --exclude=DEBIAN "$work_dir" | cut -f1)"
{
  echo "Package: $package"
  echo "Version: $version"
  echo "Architecture: $arch"
  echo "Maintainer: $maintainer"
  echo "Installed-Size: $installed_size"
  if [ -n "$depends" ]; then
    echo "Depends: $depends"
  fi
  echo "Section: $section"
  echo "Priority: ${priority:-optional}"
  echo "Homepage: $homepage"
  echo "Description: $description"
} > "$work_dir/DEBIAN/control"

# Launcher symlink next to the application directory, e.g.
# /usr/local/lib/<package>/<command> -> /usr/local/bin/<command>.
bin_subpath="$(dirname "$parent_dir")/bin"
bin_subpath="${bin_subpath#/}"
link_target="../$(basename "$parent_dir")/$package/$command_name"
mkdir -p "$work_dir/$bin_subpath"
ln -sfn "$link_target" "$work_dir/$bin_subpath/$command_name"

# Move the launcher icon into the hicolor icon theme so that the desktop
# entry (Icon=<package>) resolves.
shopt -s nullglob
icon_files=("$work_dir"/usr/share/icons/*.png)
shopt -u nullglob
if [ ${#icon_files[@]} -gt 0 ]; then
  mkdir -p "$work_dir/$icon_theme_dir"
  for icon_file in "${icon_files[@]}"; do
    mv "$icon_file" "$work_dir/$icon_theme_dir/"
  done
  rmdir "$work_dir/usr/share/icons" 2>/dev/null || true
else
  echo "warning: no launcher icon found in usr/share/icons" >&2
fi

echo "==> Repacking as root:root"
mkdir -p dist
out_deb="dist/$deb_name"
dpkg-deb --root-owner-group -b "$work_dir" "$out_deb"

echo "==> Writing and verifying checksum"
(
  cd dist
  sha256sum "$deb_name" > "$deb_name.sha256"
  sha256sum -c "$deb_name.sha256"
)

echo
echo "Package : $repo_root/$out_deb"
echo "Checksum: $repo_root/$out_deb.sha256"
cat "$out_deb.sha256"
