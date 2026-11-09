#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
version=2.10.1
expected=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
cache="$project_root/build/dependencies"
runtime="$cache/sparkle-$version"
archive="$cache/Sparkle-$version.tar.xz"
mkdir -p "$cache"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 2 --output "$archive.partial" "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz"
  mv "$archive.partial" "$archive"
fi
actual=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
[[ "$actual" == "$expected" ]] || { print -u2 'Sparkle archive checksum mismatch'; exit 1; }
if [[ ! -d "$runtime/Sparkle.framework" || ! -x "$runtime/bin/sign_update" ]]; then
  mkdir -p "$runtime"
  tar -xf "$archive" -C "$runtime" ./Sparkle.framework ./bin ./LICENSE
fi
codesign --verify --deep --strict "$runtime/Sparkle.framework"
print -r -- "$runtime"
