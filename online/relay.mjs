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

const PORT = Number(process.env.PORT ?? 5178);
const MAX_SEATS = 4;
const GRACE_MS = 30000; // 일시 끊김 시 좌석 유지(재접속 대기) 시간

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
      return json(200, { ok: sb.ok || fb.ok, supabase: sb, firestore: fb });
    }
    if (req.method === "GET" && url === "/leaderboard") return json(200, await leaderboard());
    return json(200, { ok: true, service: "rune-rivals-relay", rooms: rooms.size, db: sbReady, firestore: fbReady });
  } catch (e) { return json(500, { ok: false, error: String(e?.message || e) }); }
});

const wss = new WebSocketServer({ server });

/** code -> { code, name, members:Map<seat,{ws,name,token}>, spectators:Set<ws>, status, grace:Map, hostSeat } */
const rooms = new Map();
const lobbySubs = new Set();
let codeSeq = 0;

const send = (ws, obj) => { if (ws && ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj)); };
const hostOf = (r) => r.members.get(r.hostSeat)?.ws;
const rosterOf = (r) => [...r.members.entries()].map(([seat, m]) => ({ seat, name: m.name, on: !!m.ws })).sort((a, b) => a.seat - b.seat);
function firstFreeSeat(r) { for (let s = 0; s < MAX_SEATS; s++) if (!r.members.has(s)) return s; return -1; }
const roomInfo = (r) => ({ code: r.code, name: r.name, players: r.members.size, max: MAX_SEATS, status: r.status, spectators: r.spectators.size });
const roomList = () => [...rooms.values()].map(roomInfo);
function pushLobby() { const rl = roomList(); for (const w of lobbySubs) send(w, { t: "rooms", rooms: rl }); }
function broadcastRoster(r) { const roster = rosterOf(r); const hostSeat = r.hostSeat; for (const m of r.members.values()) send(m.ws, { t: "roster", roster, hostSeat }); for (const w of r.spectators) send(w, { t: "roster", roster, hostSeat }); }

wss.on("connection", (ws) => {
  ws.meta = { code: null, seat: -1, role: "none" };

  ws.on("message", (raw) => {
    let msg; try { msg = JSON.parse(raw.toString()); } catch { return; }

    switch (msg.t) {
      case "watch-lobby":
        lobbySubs.add(ws);
        send(ws, { t: "rooms", rooms: roomList() });
        return;

      case "create": {
        const code = `r${++codeSeq}`;
        const nick = String(msg.name ?? "P1").slice(0, 20);
        const token = randomUUID();
        const r = { code, name: String(msg.roomName ?? `${nick}의 방`).slice(0, 24), members: new Map(), spectators: new Set(), status: "waiting", grace: new Map(), hostSeat: 0 };
        r.members.set(0, { ws, name: nick, token });
        rooms.set(code, r);
        ws.meta = { code, seat: 0, role: "host", name: nick };
        send(ws, { t: "joined", code, seat: 0, isHost: true, roster: rosterOf(r), token, hostSeat: r.hostSeat });
        pushLobby();
        console.log(`[relay] create ${code} "${r.name}" host=${nick}`);
        return;
      }

      case "join": {
        const r = rooms.get(String(msg.code));
        if (!r) { send(ws, { t: "err", msg: "존재하지 않는 방입니다." }); return; }
        if (r.status !== "waiting") { send(ws, { t: "err", msg: "이미 시작된 방입니다. 관전만 가능합니다." }); return; }
        if (ws.meta.seat >= 0) return;
        const seat = firstFreeSeat(r);
        if (seat < 0) { send(ws, { t: "full" }); return; }
        const nick = String(msg.name ?? `P${seat + 1}`).slice(0, 20);
        const token = randomUUID();
        r.members.set(seat, { ws, name: nick, token });
        ws.meta = { code: r.code, seat, role: "player", name: nick };
        send(ws, { t: "joined", code: r.code, seat, isHost: false, roster: rosterOf(r), token, hostSeat: r.hostSeat });
        broadcastRoster(r);
        const h = hostOf(r); if (h) send(h, { t: "resend" });
        pushLobby();
        return;
      }

      case "reconnect": {
        const r = rooms.get(String(msg.code));
        if (!r) { send(ws, { t: "reconnect-fail" }); return; }
        let found = -1;
        for (const [seat, m] of r.members) if (m.token && m.token === msg.token) { found = seat; break; }
        if (found < 0) { send(ws, { t: "reconnect-fail" }); return; }
        const g = r.grace.get(found); if (g) { clearTimeout(g); r.grace.delete(found); }
        const m = r.members.get(found);
        m.ws = ws;
        const isHost = found === r.hostSeat;
        ws.meta = { code: r.code, seat: found, role: isHost ? "host" : "player", name: m.name };
        send(ws, { t: "joined", code: r.code, seat: found, isHost, roster: rosterOf(r), token: m.token, hostSeat: r.hostSeat });
        broadcastRoster(r);
        if (!isHost) { const h = hostOf(r); if (h) send(h, { t: "resend" }); }
        pushLobby();
        console.log(`[relay] reconnect ${r.code} seat=${found}`);
        return;
      }

      case "spectate": {
        const r = rooms.get(String(msg.code));
        if (!r) { send(ws, { t: "err", msg: "존재하지 않는 방입니다." }); return; }
        r.spectators.add(ws);
        const specName = String(msg.name ?? "관전자").slice(0, 20);
        ws.meta = { code: r.code, seat: -1, role: "spectator", name: specName };
        send(ws, { t: "spectating", code: r.code, roster: rosterOf(r), hostSeat: r.hostSeat });
        const h = hostOf(r); if (h) send(h, { t: "resend" });
        pushLobby();
        return;
      }

      case "status": {
        const r = rooms.get(ws.meta.code);
        if (r && ws.meta.seat === r.hostSeat) { r.status = String(msg.status ?? "waiting"); pushLobby(); }
        return;
      }

      case "relay": {
        const r = rooms.get(ws.meta.code);
        if (!r) return;
        if (ws.meta.role === "host") {
          for (const [s, m] of r.members) if (s !== r.hostSeat && m.ws) send(m.ws, { t: "relay", fromSeat: r.hostSeat, payload: msg.payload });
          for (const w of r.spectators) send(w, { t: "relay", fromSeat: r.hostSeat, payload: msg.payload });
        } else if (ws.meta.role === "player") {
          const h = hostOf(r); if (h) send(h, { t: "relay", fromSeat: ws.meta.seat, payload: msg.payload });
        }
        return;
      }

      case "leave": { removeFromRoom(ws, true); return; }

      case "chat": {
        const r = rooms.get(ws.meta.code);
        if (!r) return;
        const text = String(msg.text ?? "").slice(0, 300);
        if (!text.trim()) return;
        const name = ws.meta.name || (ws.meta.seat >= 0 ? r.members.get(ws.meta.seat)?.name : "관전자") || "익명";
        const payload = { t: "chat", seat: ws.meta.seat, name, text, spectator: ws.meta.role === "spectator" };
        for (const m of r.members.values()) send(m.ws, payload);
        for (const w of r.spectators) send(w, payload);
        return;
      }

      case "leave-lobby":
        lobbySubs.delete(ws);
        return;
    }
  });

  ws.on("close", () => {
    lobbySubs.delete(ws);
    removeFromRoom(ws, false);
  });
});

/** 방에서 소켓 제거. immediate=false 면 좌석을 유예시간 동안 유지(재접속 대기). */
function removeFromRoom(ws, immediate) {
  const { code, seat, role } = ws.meta;
  if (code == null) return;
  const r = rooms.get(code);
  if (!r) return;
  if (role === "spectator") { r.spectators.delete(ws); ws.meta = { code: null, seat: -1, role: "none" }; pushLobby(); return; }
  const m = r.members.get(seat);
  if (!m) return;

  const finalize = () => {
    r.grace.delete(seat);
    r.members.delete(seat);
    if (r.members.size === 0) {
      for (const w of r.spectators) send(w, { t: "host-left" });
      rooms.delete(code);
      console.log(`[relay] close room ${code} (empty)`);
      pushLobby();
      return;
    }
    if (seat === r.hostSeat) {
      const keys = [...r.members.keys()];
      const newHost = keys[Math.floor(Math.random() * keys.length)];
      r.hostSeat = newHost;
      const nm = r.members.get(newHost);
      if (nm && nm.ws) { nm.ws.meta.role = "host"; send(nm.ws, { t: "promote", hostSeat: newHost, roster: rosterOf(r) }); }
      broadcastRoster(r);
      console.log(`[relay] host migrated ${code} -> seat ${newHost}`);
    } else {
      broadcastRoster(r);
      const h = hostOf(r); if (h) send(h, { t: "resend" });
    }
    pushLobby();
  };

  if (immediate) { ws.meta = { code: null, seat: -1, role: "none" }; finalize(); return; }
  m.ws = null;
  broadcastRoster(r);
  pushLobby();
  const existing = r.grace.get(seat); if (existing) clearTimeout(existing);
  r.grace.set(seat, setTimeout(finalize, GRACE_MS));
}

server.listen(PORT, "0.0.0.0", () => {
  const ips = [];
  for (const list of Object.values(networkInterfaces())) for (const ni of list ?? []) if (ni.family === "IPv4" && !ni.internal) ips.push(ni.address);
  console.log(`\n🎴 룬 라이벌즈 릴레이 (포트 ${PORT}) — 다중 방/관전/재접속`);
  console.log(`   로컬:  ws://localhost:${PORT}`);
  for (const ip of ips) console.log(`   같은망: ws://${ip}:${PORT}`);
  console.log("");
});
