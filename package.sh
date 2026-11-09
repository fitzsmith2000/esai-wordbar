#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

zsh build.sh
version=$(plutil -extract CFBundleShortVersionString raw Info.plist)
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/public/payload/Applications" "$staging/public/image" "$staging/update"
ditto "build/esai单词.app" "$staging/update/esai单词.app"
if [[ -f "$staging/update/esai单词.app/Contents/Resources/collins.sqlite" ]]; then
  rm "$staging/update/esai单词.app/Contents/Resources/collins.sqlite"
fi
codesign --force --sign - "$staging/update/esai单词.app" >/dev/null
codesign --verify --deep --strict "$staging/update/esai单词.app"
ditto "$staging/update/esai单词.app" "$staging/public/payload/Applications/esai单词.app"
ditto "$staging/update/esai单词.app" "$staging/public/image/esai单词.app"
ln -s /Applications "$staging/public/image/应用程序"

pkgbuild --root "$staging/public/payload" --install-location / \
  --identifier com.esai.wordbar.installer --version "$version" \
  --ownership recommended "build/esai-wordbar-$version-public.pkg"
hdiutil create -volname "esai单词" -srcfolder "$staging/public/image" -format UDZO \
  -imagekey zlib-level=9 -ov "build/esai-wordbar-$version-public.dmg" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$staging/update/esai单词.app" "build/esai-wordbar-$version-apple-silicon.zip"

if [[ -s "build/esai单词.app/Contents/Resources/collins.sqlite" ]]; then
  mkdir -p "$staging/personal/payload/Applications" "$staging/personal/image"
  ditto "build/esai单词.app" "$staging/personal/payload/Applications/esai单词.app"
  ditto "build/esai单词.app" "$staging/personal/image/esai单词.app"
  ln -s /Applications "$staging/personal/image/应用程序"
  pkgbuild --root "$staging/personal/payload" --install-location / \
    --identifier com.esai.wordbar.installer --version "$version" \
    --ownership recommended "build/esai单词-$version.pkg"
  hdiutil create -volname "esai单词" -srcfolder "$staging/personal/image" -format UDZO \
    -imagekey zlib-level=9 -ov "build/esai单词-$version.dmg" >/dev/null
  print "$(pwd)/build/esai单词-$version.pkg"
  print "$(pwd)/build/esai单词-$version.dmg"
fi
print "$(pwd)/build/esai-wordbar-$version-public.pkg"
print "$(pwd)/build/esai-wordbar-$version-public.dmg"
print "$(pwd)/build/esai-wordbar-$version-apple-silicon.zip"
