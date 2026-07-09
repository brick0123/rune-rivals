// 배포된 공개 릴레이 스모크 테스트: 두 클라이언트가 인터넷 너머 서버에 붙어 방 생성/참가/상태 브로드캐스트/액션 릴레이 확인.
// 실행: RELAY_URL=wss://rune-rivals-relay.onrender.com node smoke-public.mjs
import { WebSocket } from "ws";

const URL = process.env.RELAY_URL || "wss://rune-rivals-relay.onrender.com";
let fails = 0;
const ok = (c, m) => { if (!c) { fails++; console.log("  ❌ " + m); } else console.log("  ✅ " + m); };
const wait = (ms) => new Promise(r => setTimeout(r, ms));
function client() {
  const ws = new WebSocket(URL); ws.inbox = [];
  ws.on("message", d => ws.inbox.push(JSON.parse(d.toString())));
  return new Promise((res, rej) => { ws.on("open", () => res(ws)); ws.on("error", rej); });
}
const sendJ = (ws, o) => ws.send(JSON.stringify(o));
const last = (ws, t) => [...ws.inbox].reverse().find(m => m.t === t);

console.log(`대상: ${URL}`);
try {
  const host = await client();
  sendJ(host, { t: "create", name: "호스트", roomName: "온라인테스트" });
  await wait(500);
  const j = last(host, "joined");
  ok(j && j.isHost && j.seat === 0, "공개 서버에 방 생성(seat 0)");
  const code = j.code;

  const guest = await client();
  sendJ(guest, { t: "join", code, name: "게스트" });
  await wait(500);
  ok(last(guest, "joined")?.seat === 1, "다른 클라이언트 참가(seat 1)");

  sendJ(host, { t: "relay", payload: { kind: "state", turn: 7 } });
  await wait(400);
  ok(last(guest, "relay")?.payload?.turn === 7, "호스트→게스트 상태 브로드캐스트");

  sendJ(guest, { t: "relay", payload: { kind: "action", type: "acquire" } });
  await wait(400);
  ok(last(host, "relay")?.payload?.type === "acquire", "게스트→호스트 액션 릴레이");

  host.close(); guest.close();
  await wait(200);
} catch (e) { fails++; console.log("  ❌ 연결/예외:", e.message); }
console.log(fails === 0 ? "\n✅ 공개 서버 온라인 릴레이 동작 확인" : `\n❌ ${fails}건 실패`);
process.exit(fails === 0 ? 0 : 1);
