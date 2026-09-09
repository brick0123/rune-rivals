#!/usr/bin/env bash
# 릴레이 무중단(롤링) 배포 — 드레인 방식.
# 각 인스턴스를 재시작하기 "전에" Caddy 풀에서 먼저 빼고(reload) 재시작 → 복귀.
# 재시작 중인 인스턴스로는 새 요청이 절대 가지 않아 서비스 요청 실패 0.
# 진행 중 게임은 Redis 공유상태 + 클라 자동재접속으로 유지된다.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/google-cloud-sdk/bin:$PATH"
ZONE=asia-northeast3-a; PROJECT=runecollect-relay; VM=relay

echo "▶ 코드 업로드"
gcloud compute scp online/relay.mjs online/lib/bus.mjs online/lib/store.mjs \
  "$VM":/tmp/ --zone "$ZONE" --project "$PROJECT" --quiet

echo "▶ 배치 + 문법검사 + 드레인 롤링 재시작"
gcloud compute ssh "$VM" --zone "$ZONE" --project "$PROJECT" --quiet --command '
set -e
sudo cp /tmp/relay.mjs /opt/relay/relay.mjs
sudo cp /tmp/bus.mjs   /opt/relay/lib/bus.mjs
sudo cp /tmp/store.mjs /opt/relay/lib/store.mjs
node --check /opt/relay/relay.mjs

caddyfile(){   # 인자 = 풀에 넣을 포트들
  local ups=""; for p in "$@"; do ups="$ups localhost:$p"; done
  sudo tee /etc/caddy/Caddyfile >/dev/null <<EOF
34.64.100.222.sslip.io {
	reverse_proxy$ups {
		lb_policy round_robin
		lb_try_duration 5s
		health_uri /
		health_interval 3s
		health_timeout 2s
		fail_duration 10s
	}
}
EOF
  sudo systemctl reload caddy
}
wait_healthy(){ for i in $(seq 1 30); do curl -sf "localhost:$1/" >/dev/null && return 0; sleep 0.5; done; return 1; }

roll(){   # $1=재시작 대상, $2=남겨둘 인스턴스
  echo "  - $1 드레인(풀에서 제외) → 재시작 → 복귀"
  caddyfile "$2"                        # 대상 제외, 남은 하나로만 서비스
  sleep 1                               # 진행 중 요청이 남은 인스턴스로 넘어가도록
  sudo systemctl restart "relay@$1"
  wait_healthy "$1" || { echo "    ❌ $1 헬스 실패"; exit 1; }
  caddyfile 5178 5179                   # 둘 다 복귀
  sleep 2
}
roll 5178 5179
roll 5179 5178
echo "rolling done (both healthy)"
' 2>&1 | grep -vE "Warning|Updating|^\s*$"
echo "✅ 무중단 배포 완료."
