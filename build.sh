#!/bin/bash
set -e

# Clean build cache if project was moved
if [ -d ".build" ]; then
    CACHED_PATH=$(cat .build/arm64-apple-macosx/release/build/StudyNotch.build/StudyNotch.swiftmodule 2>/dev/null | grep -o '/.*StudyNotch' | head -1 || echo "")
    CURRENT_PATH=$(pwd)
    if [ -n "$CACHED_PATH" ] && [[ "$CACHED_PATH" != *"$CURRENT_PATH"* ]]; then
        echo "🧹 Project moved — cleaning build cache..."
        rm -rf .build
    fi
fi

echo "🔨 Building StudyNotch..."
swift build -c release

echo "📦 Creating .app bundle..."

# ── ALWAYS install to /Applications so TCC always sees the same path+binary ──
# Building to a temp folder then running from there creates a new TCC entry
# every time because the path changes. /Applications gives a stable location.
APP="/Applications/StudyNotch.app"

# Kill existing instance first
killall StudyNotch 2>/dev/null || true
sleep 0.3

# Remove old bundle so codesign doesn't conflict
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/StudyNotch "$APP/Contents/MacOS/StudyNotch"
cp StudyNotch/Info.plist     "$APP/Contents/Info.plist"
cp StudyNotch/AppIcon.icns   "$APP/Contents/Resources/AppIcon.icns"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

echo "🔐 Signing..."
codesign --force --deep --sign - \
    --entitlements StudyNotch/StudyNotch.entitlements \
    "$APP"

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "✅ Installed to /Applications/StudyNotch.app"
echo "🚀 Launching..."
open "$APP"

echo ""
echo "👀 Look for the 🎓 icon in your menu bar."
echo "   Only ONE Accessibility entry will appear — at /Applications/StudyNotch.app"
echo "   You only need to approve it once, ever."
