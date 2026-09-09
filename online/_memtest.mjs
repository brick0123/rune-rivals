import { WebSocket } from "ws";
const URL="ws://localhost:5186"; const out=[];
function mk(name){return new Promise((res)=>{const ws=new WebSocket(URL);ws._name=name;ws.on("open",()=>ws.send(JSON.stringify({t:"queue",name})));ws.on("message",(d)=>{const m=JSON.parse(d.toString());if(m.t==="joined"){ws._seat=m.seat;out.push(`${name} joined seat=${m.seat} host=${m.isHost} roster=${m.roster.map(r=>r.name)}`);res(ws);}else if(m.t==="relay")out.push(`${name}(s${ws._seat}) recv from=${m.fromSeat} k=${m.payload.k}`);});});}
const [a,b]=await Promise.all([mk("A"),mk("B")]);
b.send(JSON.stringify({t:"relay",payload:{k:"ready"}}));           // 게스트→호스트
await new Promise(r=>setTimeout(r,200));
a.send(JSON.stringify({t:"relay",payload:{k:"snap",seat:0}}));     // 호스트→전원
await new Promise(r=>setTimeout(r,300));
console.log(out.join("\n"));
process.exit(0);
