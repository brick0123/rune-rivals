#!/usr/bin/env bash
# 룬컬렉트 자동 배포: 버전(빌드번호) 자동 부여 → 아카이브 → TestFlight 업로드.
# 빌드번호 = git 커밋 수(단조 증가). ASC API 키로 인증(비밀번호 불필요).
#
# 사용: scripts/release.sh
# 사전: ~/.appstoreconnect/runecollect.env (ASC_KEY_ID, ASC_ISSUER_ID)
#       ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
set -euo pipefail

cd "$(dirname "$0")/.."   # 저장소 루트

ENV_FILE="$HOME/.appstoreconnect/runecollect.env"
[ -f "$ENV_FILE" ] || { echo "❌ $ENV_FILE 없음 (ASC_KEY_ID/ASC_ISSUER_ID 필요)"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
P8="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[ -f "$P8" ] || { echo "❌ 키 파일 없음: $P8"; exit 1; }

BUILD="$(git rev-list --count HEAD)"     # 커밋 수 = 빌드번호
ARCHIVE="build/RuneRivals-${BUILD}.xcarchive"
EXPORT="build/export-${BUILD}"
AUTH=(-authenticationKeyPath "$P8" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -allowProvisioningUpdates)

echo "▶ 빌드번호 ${BUILD} — 프로젝트 생성"
xcodegen generate >/dev/null

echo "▶ 아카이브 (Release)"
xcodebuild -scheme RuneRivals -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  "${AUTH[@]}" \
  archive

echo "▶ TestFlight 업로드"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  "${AUTH[@]}"

echo "✅ 업로드 완료 (빌드 ${BUILD})."
echo "   App Store Connect → 룬컬렉트 → TestFlight 에서 처리(수 분) 후 설치 가능."
