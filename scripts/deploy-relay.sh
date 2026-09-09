#!/usr/bin/env bash
# 릴레이 무중단(롤링) 배포: VM의 2 인스턴스(relay@5178, relay@5179)를 하나씩 재시작.
# 한 인스턴스가 내려가는 동안 다른 인스턴스가 서비스 → 서비스 무중단.
# 게임 상태는 Redis 공유 + 클라 자동재접속으로 유지되어 진행 중 게임도 안 끊긴다.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/google-cloud-sdk/bin:$PATH"
ZONE=asia-northeast3-a; PROJECT=runecollect-relay; VM=relay

echo "▶ 코드 업로드"
gcloud compute scp online/relay.mjs online/lib/bus.mjs online/lib/store.mjs \
  "$VM":/tmp/ --zone "$ZONE" --project "$PROJECT" --quiet

echo "▶ 배치 + 문법검사 + 롤링 재시작"
gcloud compute ssh "$VM" --zone "$ZONE" --project "$PROJECT" --quiet --command '
set -e
sudo cp /tmp/relay.mjs /opt/relay/relay.mjs
sudo cp /tmp/bus.mjs   /opt/relay/lib/bus.mjs
sudo cp /tmp/store.mjs /opt/relay/lib/store.mjs
node --check /opt/relay/relay.mjs
wait_healthy(){ for i in $(seq 1 20); do curl -sf "localhost:$1/" >/dev/null && return 0; sleep 0.5; done; return 1; }
for PORT in 5178 5179; do
  echo "  - relay@$PORT 재시작"
  sudo systemctl restart "relay@$PORT"
  wait_healthy "$PORT" && echo "    ok($PORT)" || { echo "    ❌ $PORT 헬스 실패"; exit 1; }
  sleep 2   # 다음 인스턴스 내리기 전 안정화(Caddy가 살아있는 쪽으로 라우팅)
done
' 2>&1 | grep -vE "Warning|Updating|^\s*$"
echo "✅ 무중단 배포 완료 — 5178→5179 순차 재시작, 항상 하나는 서비스."
