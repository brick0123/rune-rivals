// 릴레이 프로토콜 로컬 검증: 서버 기동 → 호스트/게스트 접속 → 로비·생성·참가·상태 브로드캐스트·액션 릴레이 확인.
// 실행: node test-relay.mjs  (같은 폴더에서, ws 설치 필요)
import { spawn } from "node:child_process";
import { WebSocket } from "ws";

const PORT = 5199;
const URL = `ws://localhost:${PORT}`;
let fails = 0;
const ok = (c, m) => { if (!c) { fails++; console.log("  ❌ " + m); } else console.log("  ✅ " + m); };
const wait = (ms) => new Promise(r => setTimeout(r, ms));

function client() {
  const ws = new WebSocket(URL);
  ws.inbox = [];
  ws.on("message", (d) => ws.inbox.push(JSON.parse(d.toString())));
  return new Promise((res) => ws.on("open", () => res(ws)));
}
const sendJ = (ws, o) => ws.send(JSON.stringify(o));
const last = (ws, t) => [...ws.inbox].reverse().find(m => m.t === t);

const srv = spawn("node", ["relay.mjs"], { env: { ...process.env, PORT: String(PORT) }, stdio: "ignore" });
await wait(700);

try {
  // 로비 구독
  const lobby = await client();
  sendJ(lobby, { t: "watch-lobby" });
  await wait(150);
  ok(last(lobby, "rooms")?.rooms?.length === 0, "초기 로비 방 0개");

  // 호스트 방 생성
  const host = await client();
  sendJ(host, { t: "create", name: "호스트", roomName: "테스트방" });
  await wait(200);
  const joined = last(host, "joined");
  ok(joined && joined.isHost && joined.seat === 0, "호스트 생성: seat 0, isHost");
  const code = joined.code;
  ok(last(lobby, "rooms")?.rooms?.length === 1, "로비에 방 1개 반영");

  // 게스트 참가
  const guest = await client();
  sendJ(guest, { t: "join", code, name: "게스트" });
  await wait(200);
  const gj = last(guest, "joined");
  ok(gj && !gj.isHost && gj.seat === 1, "게스트 참가: seat 1");
  ok((last(host, "roster")?.roster?.length ?? 0) === 2, "호스트 로스터 2명");
  ok(last(host, "resend") !== undefined, "참가 시 호스트에 resend 요청");

  // 호스트 → 게스트 상태 브로드캐스트(relay)
  sendJ(host, { t: "relay", payload: { kind: "state", turn: 3 } });
  await wait(150);
  const rl = last(guest, "relay");
  ok(rl && rl.fromSeat === 0 && rl.payload?.turn === 3, "호스트 상태 브로드캐스트 → 게스트 수신");

  // 게스트 → 호스트 액션(relay)
  sendJ(guest, { t: "relay", payload: { kind: "action", type: "take3" } });
  await wait(150);
  const al = last(host, "relay");
  ok(al && al.fromSeat === 1 && al.payload?.type === "take3", "게스트 액션 → 호스트 수신");

  // 상태 변경(대기 → 진행) 로비 반영
  sendJ(host, { t: "status", status: "playing" });
  await wait(150);
  const rooms = last(lobby, "rooms")?.rooms ?? [];
  ok(rooms[0]?.status === "playing", "방 상태 playing 으로 로비 반영");

  await wait(100);
} catch (e) {
  fails++; console.log("  ❌ 예외:", e.message);
} finally {
  srv.kill();
  console.log(fails === 0 ? "\n✅ 릴레이 프로토콜 전부 통과" : `\n❌ ${fails}건 실패`);
  process.exit(fails === 0 ? 0 : 1);
}
