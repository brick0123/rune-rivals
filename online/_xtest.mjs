import { WebSocket } from "ws";
const out=[];
function mk(name,port){return new Promise((res)=>{const ws=new WebSocket("ws://localhost:"+port);ws._name=name;ws.on("open",()=>ws.send(JSON.stringify({t:"queue",name})));ws.on("message",(d)=>{const m=JSON.parse(d.toString());if(m.t==="joined"){ws._seat=m.seat;out.push(`${name}@${port} joined seat=${m.seat} host=${m.isHost} roster=${m.roster.map(r=>r.name)}`);res(ws);}else if(m.t==="relay")out.push(`${name}(s${ws._seat}) recv from=${m.fromSeat} k=${m.payload.k}`);});});}
const [a,b]=await Promise.all([mk("A",5187),mk("B",5188)]);   // 다른 인스턴스!
b.send(JSON.stringify({t:"relay",payload:{k:"ready"}}));
await new Promise(r=>setTimeout(r,300));
a.send(JSON.stringify({t:"relay",payload:{k:"snap",seat:0}}));
await new Promise(r=>setTimeout(r,400));
console.log(out.join("\n"));
process.exit(0);
