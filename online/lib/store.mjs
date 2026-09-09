// 공유 상태(방 멤버십 + 매칭 큐). REDIS_URL 있으면 Redis, 없으면 메모리(단일 인스턴스).
// 게임 상태는 보관하지 않는다(호스트 권위) — 좌석↔인스턴스/이름/토큰/접속여부 + 매칭 큐만.
// 모든 메서드는 async(메모리 구현도 Promise 반환) — 호출부가 동일 인터페이스로 동작.

/** redis(ioredis 인스턴스) 있으면 Redis 스토어, 없으면 메모리 스토어 반환. */
export function createStore(redis) {
  return redis ? redisStore(redis) : memoryStore();
}

// ── 메모리 구현 (단일 인스턴스) ─────────────────────────────
function memoryStore() {
  const rooms = new Map(); // code -> { name, status, hostSeat, members:Map<seat,{instanceId,name,token,connected}> }
  const snaps = new Map(); // code -> 최신 게임 스냅샷 payload(문자열) — 호스트 이양용
  const queue = [];        // { instanceId, connId, name, ts }
  return {
    mode: "memory",
    async setSnap(code, s) { snaps.set(code, s); },
    async getSnap(code) { return snaps.get(code) ?? null; },
    async createRoom(code, { name, hostSeat = 0 }) {
      rooms.set(code, { name, status: "waiting", hostSeat, members: new Map() });
    },
    async getRoom(code) {
      const r = rooms.get(code);
      if (!r) return null;
      const members = {};
      for (const [seat, m] of r.members) members[seat] = { ...m };
      return { name: r.name, status: r.status, hostSeat: r.hostSeat, members };
    },
    async setStatus(code, status) { const r = rooms.get(code); if (r) r.status = status; },
    async setHostSeat(code, seat) { const r = rooms.get(code); if (r) r.hostSeat = seat; },
    async addMember(code, seat, m) { const r = rooms.get(code); if (r) r.members.set(seat, { ...m, connected: true }); },
    async setConnected(code, seat, on) { const r = rooms.get(code); const m = r && r.members.get(seat); if (m) m.connected = !!on; },
    async removeMember(code, seat) {
      const r = rooms.get(code); if (!r) return -1;
      r.members.delete(seat);
      const n = r.members.size;
      if (n === 0) { rooms.delete(code); snaps.delete(code); }
      return n;
    },
    async deleteRoom(code) { rooms.delete(code); snaps.delete(code); },
    async firstFreeSeat(code, maxSeats) {
      const r = rooms.get(code); if (!r) return -1;
      for (let s = 0; s < maxSeats; s++) if (!r.members.has(s)) return s;
      return -1;
    },
    async listRooms() {
      return [...rooms.entries()].map(([code, r]) => ({ code, name: r.name, status: r.status, players: r.members.size }));
    },
    async enqueue(item) {
      if (queue.some((q) => q.connId === item.connId)) return;
      queue.push({ ...item, ts: Date.now() });
    },
    async dequeue(connId) { const i = queue.findIndex((q) => q.connId === connId); if (i >= 0) queue.splice(i, 1); },
    async queueLen() { return queue.length; },
    /** min~max 명이 있으면 원자적으로 뽑아 반환(없으면 []). */
    async tryMatch(min, max) {
      if (queue.length < min) return [];
      return queue.splice(0, Math.min(queue.length, max));
    },
  };
}

// ── Redis 구현 (다중 인스턴스) ─────────────────────────────
// 키: room:<code> (hash: name/status/hostSeat/m:<seat>=json), rooms(set of codes), mm:queue(list of json)
const MATCH_LUA = `
local len = redis.call('LLEN', KEYS[1])
if len < tonumber(ARGV[1]) then return {} end
local n = math.min(len, tonumber(ARGV[2]))
local out = {}
for i=1,n do out[i] = redis.call('LPOP', KEYS[1]) end
return out
`;

function redisStore(redis) {
  redis.defineCommand("mmMatch", { numberOfKeys: 1, lua: MATCH_LUA });
  const rk = (code) => `room:${code}`;
  const sk = (code) => `snap:${code}`;
  return {
    mode: "redis",
    async setSnap(code, s) { await redis.set(sk(code), s, "EX", 7200); },   // 2시간 TTL(방치 방지)
    async getSnap(code) { return (await redis.get(sk(code))) ?? null; },
    async createRoom(code, { name, hostSeat = 0 }) {
      await redis.hset(rk(code), "name", name, "status", "waiting", "hostSeat", String(hostSeat));
      await redis.sadd("rooms", code);
    },
    async getRoom(code) {
      const h = await redis.hgetall(rk(code));
      if (!h || !h.name) return null;
      const members = {};
      for (const [k, v] of Object.entries(h)) {
        if (k.startsWith("m:")) { try { members[k.slice(2)] = JSON.parse(v); } catch {} }
      }
      return { name: h.name, status: h.status, hostSeat: Number(h.hostSeat ?? 0), members };
    },
    async setStatus(code, status) { await redis.hset(rk(code), "status", status); },
    async setHostSeat(code, seat) { await redis.hset(rk(code), "hostSeat", String(seat)); },
    async addMember(code, seat, m) { await redis.hset(rk(code), `m:${seat}`, JSON.stringify({ ...m, connected: true })); },
    async setConnected(code, seat, on) {
      const cur = await redis.hget(rk(code), `m:${seat}`);
      if (!cur) return;
      try { const m = JSON.parse(cur); m.connected = !!on; await redis.hset(rk(code), `m:${seat}`, JSON.stringify(m)); } catch {}
    },
    async removeMember(code, seat) {
      await redis.hdel(rk(code), `m:${seat}`);
      const h = await redis.hgetall(rk(code));
      const n = Object.keys(h).filter((k) => k.startsWith("m:")).length;
      if (n === 0) { await redis.del(rk(code)); await redis.del(sk(code)); await redis.srem("rooms", code); }
      return n;
    },
    async deleteRoom(code) { await redis.del(rk(code)); await redis.del(sk(code)); await redis.srem("rooms", code); },
    async firstFreeSeat(code, maxSeats) {
      const h = await redis.hgetall(rk(code));
      const taken = new Set(Object.keys(h).filter((k) => k.startsWith("m:")).map((k) => Number(k.slice(2))));
      for (let s = 0; s < maxSeats; s++) if (!taken.has(s)) return s;
      return -1;
    },
    async listRooms() {
      const codes = await redis.smembers("rooms");
      const out = [];
      for (const code of codes) {
        const h = await redis.hgetall(rk(code));
        if (!h || !h.name) { await redis.srem("rooms", code); continue; }
        const players = Object.keys(h).filter((k) => k.startsWith("m:")).length;
        out.push({ code, name: h.name, status: h.status, players });
      }
      return out;
    },
    async enqueue(item) { await redis.rpush("mm:queue", JSON.stringify({ ...item, ts: Date.now() })); },
    async dequeue(connId) {
      const all = await redis.lrange("mm:queue", 0, -1);
      for (const raw of all) {
        try { if (JSON.parse(raw).connId === connId) { await redis.lrem("mm:queue", 1, raw); return; } } catch {}
      }
    },
    async queueLen() { return redis.llen("mm:queue"); },
    async tryMatch(min, max) {
      const raws = await redis.mmMatch("mm:queue", String(min), String(max));
      return (raws || []).map((r) => { try { return JSON.parse(r); } catch { return null; } }).filter(Boolean);
    },
  };
}
