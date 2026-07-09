# 룬 라이벌즈 (Rune Rivals)

원작 캐릭터 "룬 라이벌즈"로 만든 스플렌더식 카드·엔진 빌딩 보드게임 iOS 앱.
15개 진화 라인(1→2→3단계) + 희귀 5 + 전설 5 = 캐릭터 55종. 규칙 엔진은 순수 Swift로
작성되어 UI 없이도 검증 가능하다.

## 구조

```
RuneRivals/
├── Package.swift                 # SPM: 엔진 라이브러리 + 검증 실행 타깃 + 테스트
├── Sources/
│   ├── RuneRivalsEngine/         # 규칙 엔진 (Foundation only, UI 무의존)
│   │   ├── Types.swift           # Color/BallColor/Tier/CardDef ...
│   │   ├── RNG.swift             # 결정론 mulberry32
│   │   ├── Balls.swift           # 구슬·상수
│   │   ├── Cards.swift           # ★ 룬 라이벌즈 카드 데이터(라인/희귀/전설)
│   │   ├── GameState.swift       # 상태·팩토리·헬퍼
│   │   ├── Actions.swift         # 합법 액션 생성
│   │   ├── Engine.swift          # 전이·종료·승자 판정
│   │   ├── Weights.swift         # 전략 가중치
│   │   └── AI.swift              # chooseStrongTurn 등 AI 정책
│   └── RuneRivalsSim/main.swift  # 불변식 검증 시뮬레이터
├── Tests/RuneRivalsEngineTests/  # XCTest 단위 테스트
├── App/                          # SwiftUI iOS 앱
│   ├── RuneRivalsApp.swift
│   ├── GameViewModel.swift       # @Observable 엔진 래퍼
│   ├── Theme.swift
│   ├── Assets.xcassets/          # 캐릭터 55종 이미지(스크립트 생성물)
│   └── Views/                    # 메뉴/보드/카드/구슬/플레이어/액션/종료
├── scripts/gen_assets.sh         # ../cards → Assets.xcassets 재생성
├── project.yml                   # XcodeGen 정의(권장)
└── RuneRivals.xcodeproj          # 손수 작성한 Xcode 16 프로젝트(도구 없이 열기용)
```

## 1) 엔진 검증 (Xcode 불필요, 이 저장소에서 검증 완료)

```bash
cd RuneRivals
swift build -c release
swift run -c release RuneRivalsSim   # 덱 구성·진화 링크·결정론·불변식 검증 (외부 의존 0)
swift test                            # 단위 테스트 — XCTest 필요(=Xcode 설치 환경)
```

> `RuneRivalsSim` 은 Foundation 만 쓰므로 CLI 전용 Swift 툴체인에서도 그대로 돈다.
> `swift test` 는 XCTest 모듈이 필요해 Xcode 가 설치된 환경에서만 실행된다.

`RuneRivalsSim` 은 2·3·4인 AI-vs-AI 게임을 시드별로 완주시키며 매 턴 불변식을 검사한다:
구슬 총량 보존 · 손패 ≤10 · 보관 ≤3 · 음수 없음 · 게임 종료 · 승자 ≥18점 · 같은 시드 재현.

## 2) iOS 앱 실행 (Xcode 16+, iOS 17+)

**방법 A — 그대로 열기 (권장, 도구 불필요)**
```bash
open RuneRivals.xcodeproj
# 시뮬레이터 선택 후 ⌘R
```

**방법 B — XcodeGen 으로 재생성** (프로젝트가 안 열릴 경우)
```bash
brew install xcodegen
xcodegen generate
open RuneRivals.xcodeproj
```

두 방법 모두 엔진 소스(`Sources/RuneRivalsEngine`)를 앱 타깃에 직접 컴파일한다(별도 패키지 링크 없음).

## 게임 규칙 요약

- 자기 차례에 하나: ①서로 다른 구슬 3개 ②같은 구슬 2개(공급 ≥4) ③카드 보관(+궁극의 룬 오브)
  ④카드 획득(보너스로 비용 할인, 희귀/전설은 궁극의 룬 오브 필수) ⑤비공개 보관
- 행동 후 턴당 1회 **진화**(1→2→3): 획득 카드의 보너스색으로 상위 단계 획득.
  하위 카드는 점수에서 빠지지만 **보너스(할인)는 유지**된다.
- 누군가 18점 도달 시 시작 플레이어 기준 마지막 라운드까지 진행 후 종료.
- 승패: 점수 → 진화 수 → 획득 카드 수 순.

## 캐릭터 교체

캐릭터는 `../cards/{stage1,stage2,stage3,rare,legendary}/*.png` 를 사용한다.
이미지 교체·추가 후 `bash scripts/gen_assets.sh` 로 에셋 카탈로그를 재생성하면 된다.
카드 능력치(비용/점수/진화)는 `Sources/RuneRivalsEngine/Cards.swift` 에서 조정한다.

## 알려진 범위

- 게임 모드: **AI 상대** / **로컬 핫시트**(2~4인). 온라인 멀티플레이는 미포함.
- 퓨전(특정 조합 자동 획득)은 현재 로스터에 정의/이미지가 없어 제외. 필요 시 엔진에
  훅을 추가해 재도입 가능.
