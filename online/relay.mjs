// 룬 라이벌즈 온라인 릴레이 서버 (헤드리스).
// - WebSocket 릴레이만 담당: 다중 방 + 방 목록(로비) + 참가/관전 + 재접속 유예 + 호스트 이양.
// - 게임 규칙은 클라이언트(호스트=좌석 0 권위)가 처리. 서버는 방/좌석/중계만.
// - iOS 네이티브 앱이 wss://<host> 로 직접 접속(웹 HTML 서빙 불필요).
//
// 실행: PORT=5178 node relay.mjs   (또는 render.yaml 로 Render 무료 배포)

import { createServer } from "node:http";
import { networkInterfaces } from "node:os";
import { randomUUID } from "node:crypto";
import { WebSocketServer } from "ws";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { createStore } from "./lib/store.mjs";
import { createBus } from "./lib/bus.mjs";

const PORT = Number(process.env.PORT ?? 5178);
const MAX_SEATS = 3;
const GRACE_MS = 150000; // 일시 끊김 시 좌석 유지(재접속 대기) 시간 — 2.5분(백그라운드 전환·네트워크 blip 대비)

// Supabase(랭킹/집계 DB, Postgres) — 서버에만 키를 둔다. 미설정 시 전적 기능만 비활성(대전엔 영향 없음).
const SB_URL = process.env.SUPABASE_URL || "";
const SB_KEY = process.env.SUPABASE_SERVICE_KEY || "";
const sbReady = !!(SB_URL && SB_KEY);
const sbHeaders = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json" };

// Firebase Firestore(히스토리/리플레이 DB) — 서비스계정 JSON 을 env(FIREBASE_SERVICE_ACCOUNT)로 주입.
// 미설정 시 히스토리 기록만 비활성(랭킹/대전엔 영향 없음). 폴리글랏: 집계=Supabase, 히스토리=Firestore.
let firestore = null;
try {
  const rawSA = process.env.FIREBASE_SERVICE_ACCOUNT || "";
  if (rawSA) {
    // env 에 원문 JSON 또는 base64(JSON) 둘 다 허용.
    const jsonStr = rawSA.trim().startsWith("{") ? rawSA : Buffer.from(rawSA, "base64").toString("utf8");
    const cred = JSON.parse(jsonStr);
    initializeApp({ credential: cert(cred) });
    firestore = getFirestore();
  }
} catch (e) {
  console.error("[relay] Firebase 초기화 실패(히스토리 비활성):", e?.message || e);
}
const fbReady = !!firestore;

// ── 텔레그램 에러 알림 (중요 실패/에러만, 60초 중복제거) ──
const TG_TOKEN = process.env.TELEGRAM_BOT_TOKEN || "";
const TG_CHAT = process.env.TELEGRAM_CHAT_ID || "";
const tgReady = !!(TG_TOKEN && TG_CHAT);
const tgSeen = new Map(); // 메시지 dedup: key -> lastSentMs
async function notify(msg) {
  console.error("[alert]", msg);
  if (!tgReady) return;
  const key = String(msg).slice(0, 120);
  const now = Date.now();
  if (tgSeen.has(key) && now - tgSeen.get(key) < 60000) return; // 같은 알림 60초 억제(스팸 방지)
  tgSeen.set(key, now);
  if (tgSeen.size > 300) tgSeen.clear();
  try {
    await fetch(`https://api.telegram.org/bot${TG_TOKEN}/sendMessage`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: TG_CHAT, text: `🚨 [룬컬렉트 릴레이] ${msg}`.slice(0, 3900), disable_web_page_preview: true }),
    });
  } catch (e) { console.error("[tg] send fail", e?.message || e); }
}
process.on("uncaughtException", (e) => { notify(`uncaughtException: ${e?.message}\n${String(e?.stack || "").slice(0, 600)}`); });
process.on("unhandledRejection", (e) => { notify(`unhandledRejection: ${e?.message || e}`); });

// ── 스케일아웃: REDIS_URL 있으면 Redis(공유상태 + pub/sub), 없으면 메모리 단일모드 ──
const REDIS_URL = process.env.REDIS_URL || "";
const INSTANCE = randomUUID();
let redis = null, subR = null;
if (REDIS_URL) {
  try {
    const { default: IORedis } = await import("ioredis");
    const opts = { maxRetriesPerRequest: 3 };
    redis = new IORedis(REDIS_URL, opts);
    subR = new IORedis(REDIS_URL, opts);
    redis.on("error", (e) => notify(`Redis 오류: ${e?.message || e}`));
    subR.on("error", (e) => notify(`Redis(sub) 오류: ${e?.message || e}`));
    console.log(`[relay] Redis 스케일아웃 모드 (instance ${INSTANCE.slice(0, 8)})`);
  } catch (e) {
    console.error("[relay] Redis 초기화 실패 → 메모리 모드:", e?.message || e);
    redis = null; subR = null;
  }
}
const store = createStore(redis);

// 로컬 소켓 레지스트리(이 인스턴스에 실제 붙은 소켓만).
const localSockets = new Map();    // code -> Map<seat, ws>
const localSpectators = new Map(); // code -> Set<ws>
const localConns = new Map();      // connId -> ws (큐/매칭 통지용)
const lobbySubs = new Set();
let codeSeq = 0;
let matchTimer = null;
const send = (ws, obj) => { if (ws && ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj)); };

function readBody(req) {
  return new Promise((resolve) => { let b = ""; req.on("data", (c) => (b += c)); req.on("end", () => resolve(b)); });
}

/** 매치 결과 기록: matches upsert + match_results upsert. payload 는 아래 필드. */
async function recordResult(p) {
  if (!sbReady) return { ok: false, error: "db not configured" };
  const matchId = String(p.matchId || "");
  if (!matchId || !Array.isArray(p.results)) return { ok: false, error: "bad payload" };
  const match = {
    id: matchId, mode: p.mode ?? "single", room_code: p.roomCode ?? null,
    seed: p.seed ?? null, num_players: p.numPlayers ?? p.results.length,
    winner_seat: p.winnerSeat ?? null,
    started_at: p.startedAt ?? new Date().toISOString(), ended_at: p.endedAt ?? new Date().toISOString(),
  };
  const rows = p.results.map((r) => ({
    match_id: matchId, seat: r.seat, name: String(r.name ?? "?").slice(0, 20),
    points: r.points | 0, evolutions: r.evolutions | 0, cards: r.cards | 0,
    rank: r.rank | 0, is_ai: !!r.isAI,
  }));
  const mRes = await fetch(`${SB_URL}/rest/v1/matches`, {
    method: "POST", headers: { ...sbHeaders, Prefer: "resolution=merge-duplicates" }, body: JSON.stringify(match),
  });
  if (!mRes.ok) return { ok: false, error: `matches ${mRes.status}: ${await mRes.text()}` };
  const rRes = await fetch(`${SB_URL}/rest/v1/match_results`, {
    method: "POST", headers: { ...sbHeaders, Prefer: "resolution=merge-duplicates" }, body: JSON.stringify(rows),
  });
  if (!rRes.ok) return { ok: false, error: `results ${rRes.status}: ${await rRes.text()}` };
  return { ok: true };
}

/** 매치 히스토리/리플레이 기록 → Firestore matches/{matchId} (문서 id=matchId 로 멱등 upsert). */
async function recordReplay(p) {
  if (!fbReady) return { ok: false, error: "firestore not configured" };
  const matchId = String(p.matchId || "");
  if (!matchId || !Array.isArray(p.results)) return { ok: false, error: "bad payload" };
  const doc = {
    matchId,
    mode: p.mode ?? "single",
    roomCode: p.roomCode ?? null,
    seed: p.seed ?? null,
    numPlayers: p.numPlayers ?? p.results.length,
    winnerSeat: p.winnerSeat ?? null,
    results: p.results.map((r) => ({
      seat: r.seat | 0, name: String(r.name ?? "?").slice(0, 20),
      points: r.points | 0, evolutions: r.evolutions | 0, cards: r.cards | 0,
      rank: r.rank | 0, isAI: !!r.isAI,
    })),
    // 결정론 재현용(seed + 액션 로그). 클라가 보내면 저장 → 추후 서버 재시뮬 검증에 사용.
    replay: p.replay ?? p.actionLog ?? null,
    startedAt: p.startedAt ?? new Date().toISOString(),
    endedAt: p.endedAt ?? new Date().toISOString(),
    recordedAt: new Date().toISOString(),
  };
  try {
    await firestore.collection("matches").doc(matchId).set(doc, { merge: true });
    return { ok: true };
  } catch (e) {
    return { ok: false, error: String(e?.message || e) };
  }
}

async function leaderboard() {
  if (!sbReady) return { ok: false, error: "db not configured" };
  const r = await fetch(`${SB_URL}/rest/v1/player_stats?select=*&order=wins.desc,win_rate.desc&limit=50`, { headers: sbHeaders });
  if (!r.ok) return { ok: false, error: `${r.status}` };
  return { ok: true, rows: await r.json() };
}

// HTTP: 헬스체크 + 전적 기록/조회. WS 업그레이드는 아래 wss 가 처리.
const server = createServer(async (req, res) => {
  const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET,POST,OPTIONS", "Access-Control-Allow-Headers": "Content-Type" };
  const json = (code, obj) => { res.writeHead(code, { "Content-Type": "application/json; charset=utf-8", ...cors }); res.end(JSON.stringify(obj)); };
  const url = (req.url || "/").split("?")[0];
  try {
    if (req.method === "OPTIONS") { res.writeHead(204, cors); res.end(); return; }
    if (req.method === "POST" && url === "/result") {
      const body = await readBody(req);
      let payload; try { payload = JSON.parse(body); } catch { return json(400, { ok: false, error: "bad json" }); }
      // 이중 기록: Supabase(집계) 먼저 → Firestore(히스토리). 하나 실패해도 나머지는 진행.
      const sb = await recordResult(payload);
      const fb = await recordReplay(payload);
      if (!sb.ok) notify(`매치결과 기록 실패(Supabase) match=${payload?.matchId}: ${sb.error}`);
      if (!fb.ok) notify(`히스토리 기록 실패(Firestore) match=${payload?.matchId}: ${fb.error}`);
      return json(200, { ok: sb.ok || fb.ok, supabase: sb, firestore: fb });
    }
    if (req.method === "GET" && url === "/leaderboard") return json(200, await leaderboard());
    return json(200, { ok: true, service: "rune-rivals-relay", mode: store.mode, rooms: localSockets.size, db: sbReady, firestore: fbReady });
  } catch (e) { return json(500, { ok: false, error: String(e?.message || e) }); }
});

const wss = new WebSocketServer({ server });

// ── 메시지 버스: pub/sub(또는 로컬) → 로컬 소켓 전달 콜백 연결 ──
const bus = createBus({
  pub: redis, sub: subR, instance: INSTANCE,
  onRoomMsg: (code, target, msg) => deliverLocal(code, target, msg),
  onInstMsg: (payload) => { handleInstMsg(payload).catch((e) => console.error(e)); },
});

function deliverLocal(code, target, msg) {
  const seats = localSockets.get(code);
  if (seats) for (const [seat, ws] of seats) {
    if (target.kind === "all") send(ws, msg);
    else if (target.kind === "seat" && seat === target.seat) send(ws, msg);
    else if (target.kind === "exceptSeat" && seat !== target.seat) send(ws, msg);
  }
  if (target.kind === "all" || target.kind === "spectators") {
    const specs = localSpectators.get(code);
    if (specs) for (const ws of specs) send(ws, msg);
  }
}
function addLocalSocket(code, seat, ws) {
  let m = localSockets.get(code); if (!m) { m = new Map(); localSockets.set(code, m); } m.set(seat, ws);
}
function removeLocalSocket(code, seat) {
  const m = localSockets.get(code); if (m) { m.delete(seat); if (m.size === 0) localSockets.delete(code); }
}
function hasLocal(code) { return localSockets.has(code) || localSpectators.has(code); }

async function rosterOf(code) {
  const r = await store.getRoom(code); if (!r) return [];
  return Object.entries(r.members)
    .map(([seat, m]) => ({ seat: Number(seat), name: m.name, on: !!m.connected }))
    .sort((a, b) => a.seat - b.seat);
}
async function broadcastRoster(code) {
  const r = await store.getRoom(code); if (!r) return;
  bus.toRoom(code, { kind: "all" }, { t: "roster", roster: await rosterOf(code), hostSeat: r.hostSeat });
}
async function pushLobby() {
  const rooms = (await store.listRooms()).map((x) => ({ code: x.code, name: x.name, players: x.players, max: MAX_SEATS, status: x.status, spectators: 0 }));
  for (const w of lobbySubs) send(w, { t: "rooms", rooms });
}

// ── 매치메이킹 ──
async function handleInstMsg(payload) {
  if (payload.type !== "setup") return;
  const ws = localConns.get(payload.connId);
  if (!ws) return;
  ws.meta = { code: payload.code, seat: payload.seat, role: payload.isHost ? "host" : "player", name: payload.name, connId: payload.connId };
  addLocalSocket(payload.code, payload.seat, ws);
  await bus.subscribeRoom(payload.code);
  send(ws, { t: "joined", code: payload.code, seat: payload.seat, isHost: payload.isHost, roster: payload.roster, token: payload.token, hostSeat: payload.hostSeat });
}
async function enqueue(ws, name) {
  if (ws.meta.seat >= 0) return;
  await store.enqueue({ instanceId: INSTANCE, connId: ws.meta.connId, name });
  send(ws, { t: "queued", size: await store.queueLen() });
  await tryMatch(MAX_SEATS, MAX_SEATS);                    // 3명 → 즉시
  if (!matchTimer && (await store.queueLen()) >= 2) {
    matchTimer = setTimeout(() => { matchTimer = null; tryMatch(2, MAX_SEATS).catch((e) => console.error(e)); }, 8000);
  }
}
async function tryMatch(min, max) {
  const picked = await store.tryMatch(min, max);
  if (picked.length < 2) return;
  const code = `m${INSTANCE.slice(0, 4)}${++codeSeq}`;
  await store.createRoom(code, { name: "매칭", hostSeat: 0 });
  await store.setStatus(code, "playing");
  const tokens = [];
  for (let seat = 0; seat < picked.length; seat++) {
    const token = randomUUID(); tokens.push(token);
    await store.addMember(code, seat, { instanceId: picked[seat].instanceId, name: picked[seat].name, token });
  }
  const roster = await rosterOf(code);
  for (let seat = 0; seat < picked.length; seat++) {
    const p = picked[seat];
    const payload = { type: "setup", connId: p.connId, code, seat, isHost: seat === 0, roster, token: tokens[seat], hostSeat: 0, name: p.name };
    if (p.instanceId === INSTANCE) await handleInstMsg(payload);
    else bus.toInstance(p.instanceId, payload);
  }
  console.log(`[relay] match ${code} n=${picked.length}`);
}

// ── 수동 방(앱은 미사용, 호환 유지) ──
async function joinRoom(ws, code, name, asSpectator) {
  const r = await store.getRoom(code);
  if (!r) { send(ws, { t: "err", msg: "존재하지 않는 방입니다." }); return; }
  if (asSpectator) {
    let s = localSpectators.get(code); if (!s) { s = new Set(); localSpectators.set(code, s); } s.add(ws);
    ws.meta = { code, seat: -1, role: "spectator", name, connId: ws.meta.connId };
    await bus.subscribeRoom(code);
    send(ws, { t: "spectating", code, roster: await rosterOf(code), hostSeat: r.hostSeat });
    bus.toRoom(code, { kind: "seat", seat: r.hostSeat }, { t: "resend" });
    return;
  }
  if (r.status !== "waiting") { send(ws, { t: "err", msg: "이미 시작된 방입니다. 관전만 가능합니다." }); return; }
  const seat = await store.firstFreeSeat(code, MAX_SEATS);
  if (seat < 0) { send(ws, { t: "full" }); return; }
  const token = randomUUID();
  await store.addMember(code, seat, { instanceId: INSTANCE, name, token });
  ws.meta = { code, seat, role: "player", name, connId: ws.meta.connId };
  addLocalSocket(code, seat, ws);
  await bus.subscribeRoom(code);
  send(ws, { t: "joined", code, seat, isHost: false, roster: await rosterOf(code), token, hostSeat: r.hostSeat });
  await broadcastRoster(code);
  bus.toRoom(code, { kind: "seat", seat: r.hostSeat }, { t: "resend" });
}

wss.on("connection", (ws) => {
  ws.meta = { code: null, seat: -1, role: "none", connId: randomUUID() };
  localConns.set(ws.meta.connId, ws);

  ws.on("message", (raw) => {
    let msg; try { msg = JSON.parse(raw.toString()); } catch { return; }
    (async () => {
      try {
        switch (msg.t) {
          case "watch-lobby":
            lobbySubs.add(ws);
            send(ws, { t: "rooms", rooms: (await store.listRooms()).map((x) => ({ code: x.code, name: x.name, players: x.players, max: MAX_SEATS, status: x.status, spectators: 0 })) });
            return;
          case "queue": await enqueue(ws, String(msg.name ?? "플레이어").slice(0, 20)); return;
          case "dequeue": await store.dequeue(ws.meta.connId); return;
          case "create": {
            const code = `r${INSTANCE.slice(0, 4)}${++codeSeq}`;
            const nick = String(msg.name ?? "P1").slice(0, 20);
            const token = randomUUID();
            await store.createRoom(code, { name: String(msg.roomName ?? `${nick}의 방`).slice(0, 24), hostSeat: 0 });
            await store.addMember(code, 0, { instanceId: INSTANCE, name: nick, token });
            ws.meta = { code, seat: 0, role: "host", name: nick, connId: ws.meta.connId };
            addLocalSocket(code, 0, ws);
            await bus.subscribeRoom(code);
            send(ws, { t: "joined", code, seat: 0, isHost: true, roster: await rosterOf(code), token, hostSeat: 0 });
            await pushLobby();
            return;
          }
          case "join": if (ws.meta.seat < 0) await joinRoom(ws, String(msg.code), String(msg.name ?? "P").slice(0, 20), false); return;
          case "spectate": await joinRoom(ws, String(msg.code), String(msg.name ?? "관전자").slice(0, 20), true); return;
          case "reconnect": {
            const code = String(msg.code);
            const r = await store.getRoom(code);
            if (!r) { send(ws, { t: "reconnect-fail" }); return; }
            let seat = -1;
            for (const [s, m] of Object.entries(r.members)) if (m.token && m.token === msg.token) { seat = Number(s); break; }
            if (seat < 0) { send(ws, { t: "reconnect-fail" }); return; }
            const isHost = seat === r.hostSeat;
            await store.addMember(code, seat, { instanceId: INSTANCE, name: r.members[seat].name, token: msg.token });
            await store.setConnected(code, seat, true);
            ws.meta = { code, seat, role: isHost ? "host" : "player", name: r.members[seat].name, connId: ws.meta.connId };
            addLocalSocket(code, seat, ws);
            await bus.subscribeRoom(code);
            send(ws, { t: "joined", code, seat, isHost, roster: await rosterOf(code), token: msg.token, hostSeat: r.hostSeat });
            await broadcastRoster(code);
            return;
          }
          case "status": {
            const code = ws.meta.code; if (!code) return;
            const r = await store.getRoom(code);
            if (r && ws.meta.seat === r.hostSeat) { await store.setStatus(code, String(msg.status ?? "waiting")); await pushLobby(); }
            return;
          }
          case "relay": {
            const code = ws.meta.code; if (!code) return;
            const r = await store.getRoom(code); if (!r) return;
            if (ws.meta.role === "host") bus.toRoom(code, { kind: "exceptSeat", seat: r.hostSeat }, { t: "relay", fromSeat: r.hostSeat, payload: msg.payload });
            else if (ws.meta.role === "player") bus.toRoom(code, { kind: "seat", seat: r.hostSeat }, { t: "relay", fromSeat: ws.meta.seat, payload: msg.payload });
            return;
          }
          case "leave": await removeFromRoom(ws, true); return;
          case "chat": {
            const code = ws.meta.code; if (!code) return;
            const text = String(msg.text ?? "").slice(0, 300); if (!text.trim()) return;
            bus.toRoom(code, { kind: "all" }, { t: "chat", seat: ws.meta.seat, name: ws.meta.name || "익명", text, spectator: ws.meta.role === "spectator" });
            return;
          }
          case "leave-lobby": lobbySubs.delete(ws); return;
        }
      } catch (e) { console.error("[relay] msg error", e?.message || e); }
    })();
  });

  ws.on("close", () => {
    lobbySubs.delete(ws);
    (async () => {
      try {
        if (ws.meta.connId) { localConns.delete(ws.meta.connId); await store.dequeue(ws.meta.connId); }
        await removeFromRoom(ws, false);
      } catch (e) { console.error("[relay] close error", e?.message || e); }
    })();
  });
});

// 방에서 소켓 제거. immediate=false 면 유예시간 동안 좌석 유지(재접속 대기).
async function removeFromRoom(ws, immediate) {
  const { code, seat, role } = ws.meta;
  if (code == null) return;
  const r = await store.getRoom(code);
  if (!r) return;
  if (role === "spectator") {
    const s = localSpectators.get(code); if (s) { s.delete(ws); if (s.size === 0) localSpectators.delete(code); }
    ws.meta = { code: null, seat: -1, role: "none", connId: ws.meta.connId };
    if (!hasLocal(code)) await bus.unsubscribeRoom(code);
    return;
  }
  if (r.members[seat] == null) return;

  const finalize = async () => {
    const cur = await store.getRoom(code);
    const m = cur && cur.members[seat];
    if (m && m.connected) return;                 // 재접속함 → 유지
    const remaining = await store.removeMember(code, seat);
    if (remaining <= 0) { await pushLobby(); return; }
    if (seat === (cur ? cur.hostSeat : r.hostSeat)) {
      const after = await store.getRoom(code);
      const seats = after ? Object.keys(after.members).map(Number).sort((a, b) => a - b) : [];
      if (seats.length) {
        const newHost = seats[0];
        await store.setHostSeat(code, newHost);
        bus.toRoom(code, { kind: "seat", seat: newHost }, { t: "promote", hostSeat: newHost, roster: await rosterOf(code) });
      }
    }
    await broadcastRoster(code);
    await pushLobby();
  };

  if (immediate) {
    ws.meta = { code: null, seat: -1, role: "none", connId: ws.meta.connId };
    await store.setConnected(code, seat, false);
    removeLocalSocket(code, seat);
    if (!hasLocal(code)) await bus.unsubscribeRoom(code);
    await finalize();
    return;
  }
  // 유예: 접속 끊김 표시 → roster 브로드캐스트(호스트가 그 좌석 스킵), GRACE 후 완전 제거.
  await store.setConnected(code, seat, false);
  removeLocalSocket(code, seat);
  await broadcastRoster(code);
  if (!hasLocal(code)) await bus.unsubscribeRoom(code);
  setTimeout(() => { finalize().catch((e) => console.error(e)); }, GRACE_MS);
}

server.listen(PORT, "0.0.0.0", () => {
  const ips = [];
  for (const list of Object.values(networkInterfaces())) for (const ni of list ?? []) if (ni.family === "IPv4" && !ni.internal) ips.push(ni.address);
  console.log(`\n🎴 룬 라이벌즈 릴레이 (포트 ${PORT}) — 다중 방/관전/재접속`);
  console.log(`   로컬:  ws://localhost:${PORT}`);
  for (const ip of ips) console.log(`   같은망: ws://${ip}:${PORT}`);
  console.log("");
  if (tgReady) notify(`릴레이 시작됨 (mode=${store.mode}, db=${sbReady}, firestore=${fbReady})`);
});
