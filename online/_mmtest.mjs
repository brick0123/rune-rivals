import { WebSocket } from "ws";
const results = [];
function client(name) {
  return new Promise((resolve) => {
    const ws = new WebSocket("ws://localhost:5181");
    ws.on("open", () => ws.send(JSON.stringify({ t: "queue", name })));
    ws.on("message", (d) => {
      const m = JSON.parse(d.toString());
      if (m.t === "joined") { results.push(`${name}: joined seat=${m.seat} host=${m.isHost} roster=${m.roster.map(r=>r.name).join(",")}`); resolve(ws); }
    });
  });
}
const a = client("앨리스"); const b = client("밥");
await Promise.all([a, b]);
console.log(results.join("\n"));
process.exit(0);
