const http = require('http');
const path = require('path');
const os = require('os');
const fs = require('fs');
const express = require('express');
const UdpTelemetryListener = require('./udpTelemetryListener');
const FileTelemetryListener = require('./fileTelemetryListener');
const UdpDiscoveryBeacon = require('./udpDiscoveryBeacon');
const WebSocketServerHub = require('./websocketServer');
const InputSimulator = require('./inputSimulator');
const DemoSimulator = require('./demoSimulator');

const HTTP_PORT = process.env.PORT || 3000;
const WS_PORT = process.env.WS_PORT || 8080;
const UDP_TELEMETRY_PORT = process.env.UDP_PORT || 41234;
const UDP_BEACON_PORT = process.env.BEACON_PORT || 41235;

const app = express();
const server = http.createServer(app);

app.use(express.json());

// Serve static web client
const webDir = path.resolve(__dirname, '../../web');
app.use(express.static(webDir));

// Subsystems
const inputSimulator = new InputSimulator();

let latestData = null;
let useDemoFallback = true; // Auto demo when FS25 is not actively streaming

// Action file dispatching directly to FS25 Mod in-game (using GIANTS native XML API)
const actionFilePaths = [
  'D:/Documents/My Games/FarmingSimulator2025/fstel_action.xml',
  path.join(os.homedir(), 'Documents/My Games/FarmingSimulator2025/fstel_action.xml')
];

let actionSeq = 0;
function dispatchGameAction(actionName) {
  actionSeq++;
  const xmlPayload = `<action seq="${actionSeq}" name="${actionName}"/>\n`;
  for (const p of actionFilePaths) {
    try {
      fs.writeFileSync(p, xmlPayload, 'utf8');
    } catch (e) {}
  }
}

const wsHub = new WebSocketServerHub({
  port: WS_PORT,
  onClientAction: (action, raw) => {
    console.log(`[Main] Button Box Action received: ${action}`);
    dispatchGameAction(action);
    inputSimulator.triggerAction(action);
    if (useDemoFallback && demoSim) {
      demoSim.handleAction(action);
    }
  }
});

// Candidate paths for FS25 game telemetry file
const possiblePaths = [
  'D:/Documents/My Games/FarmingSimulator2025/fstel_telemetry.json',
  'D:/Documents/My Games/FarmingSimulator2025/fstel_telemetry.xml',
  path.join(os.homedir(), 'Documents/My Games/FarmingSimulator2025/fstel_telemetry.json'),
  path.join(os.homedir(), 'Documents/My Games/FarmingSimulator2025/fstel_telemetry.xml')
];

function hasLiveGameData() {
  return udpListener.hasRecentData(2500) || fileListener.hasRecentData(2500);
}

const fileListener = new FileTelemetryListener({
  paths: possiblePaths,
  intervalMs: 35,
  onTelemetryUpdate: (gameData) => {
    latestData = gameData;
    wsHub.broadcast(gameData);
  }
});

const udpListener = new UdpTelemetryListener(UDP_TELEMETRY_PORT, (gameData) => {
  latestData = gameData;
  wsHub.broadcast(gameData);
});

const demoSim = new DemoSimulator((demoData) => {
  if (useDemoFallback && !hasLiveGameData()) {
    latestData = demoData;
    wsHub.broadcast(demoData);
  }
});

const discoveryBeacon = new UdpDiscoveryBeacon({
  broadcastPort: UDP_BEACON_PORT,
  httpPort: HTTP_PORT,
  wsPort: WS_PORT
});

// REST API Endpoints
app.get('/api/status', (req, res) => {
  const hasGame = hasLiveGameData();
  const currentHz = fileListener.currentHz > 0 ? fileListener.currentHz : udpListener.currentHz;
  res.json({
    online: true,
    gameConnected: hasGame,
    demoModeActive: useDemoFallback && !hasGame,
    incomingHz: currentHz,
    connectedClients: wsHub.clients.size,
    ports: {
      http: HTTP_PORT,
      ws: WS_PORT,
      udpTelemetry: UDP_TELEMETRY_PORT,
      udpBeacon: UDP_BEACON_PORT
    },
    latestTimestamp: latestData ? latestData.timestamp : null
  });
});

app.post('/api/action', (req, res) => {
  const { action } = req.body;
  if (!action) return res.status(400).json({ error: 'Missing action parameter' });
  dispatchGameAction(action);
  const executed = inputSimulator.triggerAction(action);
  if (useDemoFallback && demoSim) {
    demoSim.handleAction(action);
  }
  res.json({ success: true, executed, action });
});

app.post('/api/demo/toggle', (req, res) => {
  useDemoFallback = !useDemoFallback;
  res.json({ demoMode: useDemoFallback });
});

// Startup sequence
async function main() {
  console.log(`\n======================================================`);
  console.log(`🚜 FSTel - Farming Simulator 25 Telemetry & Control Terminal`);
  console.log(`======================================================\n`);

  try {
    await udpListener.start();
  } catch (err) {
    console.error(`Could not bind UDP Telemetry Listener:`, err.message);
  }

  fileListener.start();
  discoveryBeacon.start();
  wsHub.start();

  // Start demo simulation ticker (active when FS25 is not sending)
  demoSim.start(25);

  server.listen(HTTP_PORT, '0.0.0.0', () => {
    console.log(`[HTTP Server] Web Terminal available at: http://localhost:${HTTP_PORT}`);
    const ips = discoveryBeacon.getLocalIpAddresses();
    if (ips.length > 0) {
      console.log(`[LAN Access] Mobile / Tablet Dashboard URL: http://${ips[0].address}:${HTTP_PORT}`);
    }
    console.log(`[Ready] Waiting for FS25 game telemetry (File IPC or UDP) or external clients...\n`);
  });
}

main().catch((err) => {
  console.error(`Fatal startup error:`, err);
});
