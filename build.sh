#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app="build/esai单词.app"
sparkle_runtime=$(zsh Scripts/fetch-sparkle.sh)
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks" "$app/Contents/Resources/Licenses"
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos13 Wordbar.swift Updates.swift \
  -framework AppKit -framework SwiftUI -framework WebKit -framework Carbon -lsqlite3 \
  -F "$sparkle_runtime" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$app/Contents/MacOS/Wordbar"
if command -v cargo >/dev/null; then
  cargo build --release --manifest-path tools/mdx_importer/Cargo.toml
elif [[ -x /opt/homebrew/opt/rustup/bin/cargo ]]; then
  PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo build --release --manifest-path tools/mdx_importer/Cargo.toml
else
  print -u2 "构建词书下载功能需要 Rust Cargo。"
  exit 1
fi
cp tools/mdx_importer/target/release/esai-mdx-importer "$app/Contents/MacOS/"
cp Info.plist "$app/Contents/Info.plist"
cp Resources/word-atlas.json Resources/EsaiStatusTemplate.pdf Resources/AppIcon.icns "$app/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md README.md tools/convert_collins.py "$app/Contents/Resources/"
ditto "$sparkle_runtime/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "$sparkle_runtime/LICENSE" "$app/Contents/Resources/Licenses/Sparkle.txt"
dictionary="$HOME/Library/Application Support/esai-wordbar/dictionaries/collins.sqlite"
if [[ -s "$dictionary" ]]; then
  cp "$dictionary" "$app/Contents/Resources/collins.sqlite"
elif [[ -s "/Applications/esai单词.app/Contents/Resources/collins.sqlite" ]]; then
  cp "/Applications/esai单词.app/Contents/Resources/collins.sqlite" "$app/Contents/Resources/collins.sqlite"
else
  rm -f "$app/Contents/Resources/collins.sqlite"
fi
codesign --force --sign - "$app/Contents/MacOS/esai-mdx-importer" >/dev/null
codesign --force --sign - "$app" >/dev/null
codesign --verify --deep --strict "$app"
echo "$PWD/$app"
