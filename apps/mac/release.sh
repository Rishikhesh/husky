#!/usr/bin/env bash
# Publish a Husky release from this Mac: ./release.sh 0.14.0
#
# Why a script and not CI: the app is signed with this Mac's Apple Development
# certificate. A stable signature keeps the microphone and accessibility
# grants across updates; an ad-hoc CI build would change it every release and
# macOS would ask again each time. This way no certificate goes into GitHub.
#
# Steps: check the notes, stamp the version, test, build, sign, make the dmg,
# commit + tag + push, publish the GitHub release, bump the Homebrew cask.
#
# Needs: xcodegen, gh (logged in as Rishikhesh, with workflow scope).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: ./release.sh MAJOR.MINOR.PATCH"; exit 1; }

REPO="Rishikhesh/husky"
TAP_REPO="Rishikhesh/homebrew-tap"
DERIVED=".build-release"
APP="${DERIVED}/Build/Products/Release/Husky.app"
DMG="Husky-${VERSION}.dmg"
# push over https as the gh account: the ssh key here belongs to another one.
GIT_AUTH=(-c credential.helper= -c "credential.helper=!gh auth git-credential")

[ -z "$(git status --porcelain)" ] || { echo "commit or stash your changes first"; exit 1; }
head -1 RELEASE_NOTES.md | grep -qx "## ${VERSION}" \
  || { echo "RELEASE_NOTES.md must start with: ## ${VERSION}"; exit 1; }
git rev-parse "v${VERSION}" >/dev/null 2>&1 && { echo "v${VERSION} already exists"; exit 1; }

IDENTITY="$(security find-identity -v -p codesigning | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')"
[ -n "$IDENTITY" ] || { echo "no Apple Development certificate in the keychain"; exit 1; }

echo "▸ stamping ${VERSION}"
BUILD_NUMBER="$(git rev-list --count HEAD)"
sed -i '' "s/CFBundleShortVersionString: \".*\"/CFBundleShortVersionString: \"${VERSION}\"/" project.yml
sed -i '' "s/CFBundleVersion: \".*\"/CFBundleVersion: \"${BUILD_NUMBER}\"/" project.yml
xcodegen generate --quiet

if [ "${SKIP_TESTS:-}" != "1" ]; then
  echo "▸ testing"
  xcodebuild test -project AndrewDictate.xcodeproj -scheme AndrewDictate -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath .build-dev CODE_SIGNING_ALLOWED=NO -quiet
fi

echo "▸ building (signing as: ${IDENTITY})"
xcodebuild build -project AndrewDictate.xcodeproj -scheme AndrewDictate -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual -quiet
codesign --force --deep -s "$IDENTITY" "$APP"
ACTUAL="$(defaults read "$PWD/${APP}/Contents/Info.plist" CFBundleShortVersionString)"
[ "$ACTUAL" = "$VERSION" ] || { echo "built app says ${ACTUAL}, expected ${VERSION}"; exit 1; }

echo "▸ dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Husky" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGE"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

echo "▸ commit, tag, push"
git add project.yml Sources/Info.plist
git commit -q -m "release ${VERSION}"
git tag "v${VERSION}"
git "${GIT_AUTH[@]}" push -q origin HEAD "v${VERSION}"

echo "▸ github release"
NOTES="$(mktemp)"
awk -v section="## ${VERSION}" '$0 == section { on = 1; next } on && /^## / { exit } on { print }' \
  RELEASE_NOTES.md > "$NOTES"
cat >> "$NOTES" <<EOF

---

Install: \`brew install --cask rishikhesh/tap/husky\`
Update: \`brew upgrade --cask rishikhesh/tap/husky\`, or click the update line in Husky's menu.

sha256: ${SHA}
EOF
gh release create "v${VERSION}" "$DMG" --repo "$REPO" --title "Husky ${VERSION}" --notes-file "$NOTES"
rm -f "$NOTES" "$DMG"

echo "▸ homebrew cask"
# a clone under ~/personal, so its commits sign with the personal key.
TAP="$HOME/personal/homebrew-tap"
[ -d "$TAP/.git" ] || gh repo clone "$TAP_REPO" "$TAP" -- -q
git -C "$TAP" "${GIT_AUTH[@]}" pull -q --ff-only
sed -i '' "s/version \".*\"/version \"${VERSION}\"/; s/sha256 \".*\"/sha256 \"${SHA}\"/" "$TAP/Casks/husky.rb"
git -C "$TAP" add Casks/husky.rb
git -C "$TAP" commit -q -m "husky ${VERSION}"
git -C "$TAP" "${GIT_AUTH[@]}" push -q origin HEAD

echo
echo "released Husky ${VERSION}: https://github.com/${REPO}/releases/tag/v${VERSION}"
echo "update: brew upgrade --cask rishikhesh/tap/husky"
