import { readFileSync } from "node:fs";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
const sa = JSON.parse(readFileSync("/Users/eren/Downloads/rune-f575d-firebase-adminsdk-fbsvc-15115cd87c.json","utf8"));
initializeApp({ credential: cert(sa) });
const db = getFirestore();
const snap = await db.collection("matches").get();
for (const d of snap.docs) { console.log("삭제:", d.id); await d.ref.delete(); }
const after = await db.collection("matches").get();
console.log("남은 matches:", after.size);
process.exit(0);
