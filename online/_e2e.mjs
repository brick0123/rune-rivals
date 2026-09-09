import { WebSocket } from "ws";
const log = [];
function mk(name) {
  return new Promise((res) => {
    const ws = new WebSocket("ws://localhost:5184");
    ws._name = name;
    ws.on("open", () => ws.send(JSON.stringify({ t: "queue", name })));
    ws.on("message", (d) => {
      const m = JSON.parse(d.toString());
      if (m.t === "joined") { ws._seat = m.seat; res(ws); }
      else if (m.t === "relay") log.push(`${ws._name}(seat${ws._seat}) recv from=${m.fromSeat} k=${m.payload.k}`);
    });
  });
}
// 동시 연결 → 둘 다 joined 대기(2인 8초 타이머)
const [host, guest] = await Promise.all([mk("호스트"), mk("게스트")]);
guest.send(JSON.stringify({ t: "relay", payload: { k: "ready" } }));
await new Promise(r => setTimeout(r, 200));
host.send(JSON.stringify({ t: "relay", payload: { k: "snap", seat: 0, phase: "main" } }));
await new Promise(r => setTimeout(r, 300));
console.log("seats: host=" + host._seat + " guest=" + guest._seat);
console.log(log.join("\n"));
process.exit(0);
