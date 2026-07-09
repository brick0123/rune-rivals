#!/usr/bin/env bash
# 캐릭터 PNG(../cards/**/*.png) → App/Assets.xcassets/<romanized>.imageset 생성.
# romanized 파일명이 전부 유니크하므로 단계 구분 없이 평탄하게 담는다 → SwiftUI `Image("kai")`.
# 실행: bash scripts/gen_assets.sh  (RuneRivals 디렉토리 기준)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CARDS="$ROOT/../cards"          # /Users/eren/spender/cards (원본, 아이콘용)
CUT="$ROOT/cutouts"             # 배경 제거(누끼) 이미지 — 카드 에셋 소스
XCASSETS="$ROOT/App/Assets.xcassets"

rm -rf "$XCASSETS"
mkdir -p "$XCASSETS"

# 루트 카탈로그
cat > "$XCASSETS/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

count=0
for png in "$CUT"/*.png; do
  [ -e "$png" ] || continue
  name="$(basename "$png" .png)"
  set="$XCASSETS/$name.imageset"
  mkdir -p "$set"
  cp "$png" "$set/$name.png"
  cat > "$set/Contents.json" <<JSON
{
  "images" : [
    {
      "idiom" : "universal",
      "filename" : "$name.png"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  count=$((count+1))
done
echo "imagesets: $count"

# AccentColor (룬 블루)
mkdir -p "$XCASSETS/AccentColor.colorset"
cat > "$XCASSETS/AccentColor.colorset/Contents.json" <<'JSON'
{
  "colors" : [
    {
      "idiom" : "universal",
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "0.204", "green" : "0.451", "blue" : "0.812", "alpha" : "1.000" }
      }
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

# AppIcon: 대표 카드(red_nova)를 1024 정사각으로 패딩. 실패 시 빈 아이콘.
mkdir -p "$XCASSETS/AppIcon.appiconset"
ICON_SRC="$CARDS/legendary/red_nova.png"
if [ -e "$ICON_SRC" ] && sips -s format png --padColor 101828 --padToHeightWidth 1024 1024 "$ICON_SRC" --out "$XCASSETS/AppIcon.appiconset/appicon.png" >/dev/null 2>&1; then
  cat > "$XCASSETS/AppIcon.appiconset/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024", "filename" : "appicon.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  echo "appicon: ok"
else
  cat > "$XCASSETS/AppIcon.appiconset/Contents.json" <<'JSON'
{
  "images" : [ { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  echo "appicon: placeholder"
fi

echo "done → $XCASSETS"
