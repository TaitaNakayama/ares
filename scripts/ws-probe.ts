import WebSocket from "ws";
const ws = new WebSocket(process.argv[2]!);
ws.on("close", (code) => { console.log("closed", code); process.exit(0); });
ws.on("message", () => { console.log("got message (accepted)"); ws.close(); });
setTimeout(() => { console.log("timeout"); process.exit(0); }, 3000);
