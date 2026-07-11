# Firebase(Firestore) 히스토리 DB 연동 가이드

폴리글랏 구성:
- **Supabase(Postgres)** — 랭킹/rating/집계 (`players`, `matches`, `match_results`, `player_stats` 뷰). 이미 연동됨.
- **Firebase Firestore** — 매치 히스토리/리플레이 (`matches/{matchId}` 도큐먼트). 이 문서에서 연동.

릴레이 코드(`relay.mjs`)는 이미 준비됨: `FIREBASE_SERVICE_ACCOUNT` env 가 있으면 `POST /result` 때
Supabase(집계) → Firestore(히스토리) **이중 기록**한다. env 없으면 히스토리만 자동 비활성(대전·랭킹 영향 없음).

---

## 1. Firebase 프로젝트 + Firestore 만들기 (콘솔)

1. https://console.firebase.google.com → **프로젝트 추가**
2. 좌측 **빌드 → Firestore Database → 데이터베이스 만들기**
   - 모드: **프로덕션 모드** (규칙은 아래 4번에서 설정)
   - 리전: 사용자와 가까운 곳 (예: `asia-northeast3` 서울)

## 2. 서비스계정 키 발급 (서버 전용)

1. ⚙️ **프로젝트 설정 → 서비스 계정** 탭
2. **새 비공개 키 생성** → JSON 파일 다운로드 (예: `serviceAccount.json`)
   - ⚠️ 이 파일은 **절대 커밋 금지**. 서버 env 로만 주입.

## 3. env 주입

릴레이는 `FIREBASE_SERVICE_ACCOUNT` 에 **JSON 원문** 또는 **base64(JSON)** 둘 다 허용.

**로컬 테스트**
```bash
cd online
# 원문 그대로
export FIREBASE_SERVICE_ACCOUNT="$(cat /path/to/serviceAccount.json)"
# (또는 base64) export FIREBASE_SERVICE_ACCOUNT="$(base64 < /path/to/serviceAccount.json)"
export SUPABASE_URL="https://xxxx.supabase.co"
export SUPABASE_SERVICE_KEY="..."
node relay.mjs
# → 헬스체크: curl localhost:5178/  →  "firestore":true 확인
```

**Render 배포**
- 대시보드 → 서비스 → **Environment** → `FIREBASE_SERVICE_ACCOUNT` 추가
  - 여러 줄 JSON 붙여넣기 어려우면 **base64 한 줄**로 넣는 걸 권장:
    `base64 < serviceAccount.json | pbcopy`
- (Supabase 키들도 같은 화면에서 입력. `render.yaml` 에 `sync:false` 로 잡혀 있음)

## 4. Firestore 보안 규칙

서버는 Admin SDK(서비스계정)라 규칙을 **우회**한다. 규칙은 **클라이언트(iOS) 직접 접근**에만 적용.

- iOS 에서 히스토리를 **읽기만** 할 거면:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    match /matches/{id} {
      allow read: if true;      // 공개 히스토리 조회 허용(원하면 auth 조건으로 강화)
      allow write: if false;    // 클라 쓰기 금지 → 기록은 서버(Admin)만
    }
  }
}
```
- iOS 에서 아예 안 읽고 서버 API 로만 노출할 거면 read 도 `if false` 로.

## 5. 검증

1. `curl <relay>/` → `{"db":true,"firestore":true}` 확인
2. 한 판 끝내기 → `POST /result` 응답 `{"ok":true,"supabase":{"ok":true},"firestore":{"ok":true}}`
3. Firebase 콘솔 → Firestore → `matches` 컬렉션에 `{matchId}` 문서 생성 확인

---

## 저장되는 히스토리 문서 (`matches/{matchId}`)

```jsonc
{
  "matchId": "…", "mode": "ranked", "roomCode": "r3", "seed": 12345,
  "numPlayers": 4, "winnerSeat": 2,
  "results": [ { "seat":0,"name":"나","points":18,"evolutions":2,"cards":9,"rank":1,"isAI":false }, … ],
  "replay": null,           // seed + 액션 로그(클라가 보내면 저장) → 추후 서버 재시뮬 검증용
  "startedAt": "…", "endedAt": "…", "recordedAt": "…"
}
```

> 다음 단계(선택): 엔진에 **결정론적 액션 로그**를 추가해 `replay` 에 담으면,
> 서버가 `seed + 액션열`을 재시뮬레이션해 랭크 결과를 **검증(anti-cheat)** 할 수 있다.
