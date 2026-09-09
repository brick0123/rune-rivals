import { WebSocket } from "ws";
const URL="wss://34.64.100.222.sslip.io"; const out=[];
function mk(name){return new Promise((res)=>{const ws=new WebSocket(URL);ws._name=name;ws.on("open",()=>ws.send(JSON.stringify({t:"queue",name})));ws.on("message",(d)=>{const m=JSON.parse(d.toString());if(m.t==="joined"){ws._seat=m.seat;out.push(`${name} joined seat=${m.seat} host=${m.isHost}`);res(ws);}else if(m.t==="relay")out.push(`${name}(s${ws._seat}) recv from=${m.fromSeat} k=${m.payload.k}`);});ws.on("error",e=>{out.push(name+" err:"+e.message);res(null);});});}
const [a,b]=await Promise.all([mk("A"),mk("B")]);
if(b) b.send(JSON.stringify({t:"relay",payload:{k:"ready"}}));
await new Promise(r=>setTimeout(r,300));
if(a) a.send(JSON.stringify({t:"relay",payload:{k:"snap",seat:0}}));
await new Promise(r=>setTimeout(r,400));
console.log(out.join("\n"));
process.exit(0);
