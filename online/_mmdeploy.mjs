import { WebSocket } from "ws";
const URL = "wss://rune-rivals-relay.onrender.com";
const out = [];
function mk(name){return new Promise((res)=>{const ws=new WebSocket(URL);ws.on("open",()=>ws.send(JSON.stringify({t:"queue",name})));ws.on("message",(d)=>{const m=JSON.parse(d.toString());if(m.t==="joined"){out.push(`${name}: seat=${m.seat} host=${m.isHost}`);res(ws);}});ws.on("error",e=>{out.push(name+" err:"+e.message);res(null);});});}
const [a,b]=await Promise.all([mk("A"),mk("B")]);
console.log(out.join("\n"));
process.exit(0);
