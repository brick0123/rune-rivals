// 방/인스턴스 대상 메시지 전달. REDIS_URL 있으면 Redis pub/sub, 없으면 로컬 직접 전달.
// 호출부가 실제 로컬 소켓 전달을 담당:
//   onRoomMsg(code, target, msg): 이 인스턴스의 로컬 소켓 중 target 에 맞는 것에 전달
//   onInstMsg(payload): 이 인스턴스로 온 직접 메시지 처리(matched 통지 등)
// target 형태: {kind:"all"} | {kind:"seat", seat} | {kind:"exceptSeat", seat} | {kind:"spectators"}

const ROOM_PREFIX = "chan:room:";

export function createBus({ pub, sub, instance, onRoomMsg, onInstMsg }) {
  const useRedis = !!(pub && sub);

  if (!useRedis) {
    return {
      mode: "memory",
      toRoom(code, target, msg) { onRoomMsg(code, target, msg); },
      toInstance(_instId, payload) { onInstMsg(payload); },
      async subscribeRoom() {},
      async unsubscribeRoom() {},
    };
  }

  const instChan = `chan:inst:${instance}`;
  sub.subscribe(instChan);
  sub.on("message", (ch, raw) => {
    let data; try { data = JSON.parse(raw); } catch { return; }
    if (ch === instChan) { onInstMsg(data); return; }
    if (ch.startsWith(ROOM_PREFIX)) onRoomMsg(ch.slice(ROOM_PREFIX.length), data.target, data.msg);
  });

  const subbed = new Set();
  return {
    mode: "redis",
    // 발행 → 그 방을 구독 중인 모든 인스턴스(자기 포함)가 onRoomMsg 로 로컬 전달.
    toRoom(code, target, msg) { pub.publish(`${ROOM_PREFIX}${code}`, JSON.stringify({ target, msg })); },
    toInstance(instId, payload) { pub.publish(`chan:inst:${instId}`, JSON.stringify(payload)); },
    async subscribeRoom(code) { if (!subbed.has(code)) { subbed.add(code); await sub.subscribe(`${ROOM_PREFIX}${code}`); } },
    async unsubscribeRoom(code) { if (subbed.has(code)) { subbed.delete(code); await sub.unsubscribe(`${ROOM_PREFIX}${code}`); } },
  };
}
