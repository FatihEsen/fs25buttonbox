const WebSocket = require('ws');

class WebSocketServerHub {
  constructor({ port = 8080, server = null, onClientAction = null }) {
    this.port = port;
    this.server = server;
    this.onClientAction = onClientAction;
    this.wss = null;
    this.clients = new Set();
  }

  start() {
    const options = this.server ? { server: this.server } : { port: this.port };
    this.wss = new WebSocket.Server(options);

    this.wss.on('connection', (ws, req) => {
      const clientIp = req.socket.remoteAddress;
      this.clients.add(ws);
      console.log(`[WebSocket Hub] Client connected from ${clientIp}. Total active clients: ${this.clients.size}`);

      // Send greeting handshake
      ws.send(JSON.stringify({
        type: 'HANDSHAKE',
        message: 'FSTel Telemetry & Button Box Bridge Connected',
        serverTime: Date.now()
      }));

      ws.on('message', (message) => {
        try {
          const payload = JSON.parse(message.toString('utf8'));
          if (payload.type === 'BUTTON_ACTION' && payload.action) {
            if (typeof this.onClientAction === 'function') {
              this.onClientAction(payload.action, payload);
            }
          } else if (payload.type === 'PING') {
            ws.send(JSON.stringify({ type: 'PONG', clientTime: payload.timestamp, serverTime: Date.now() }));
          }
        } catch (e) {
          console.warn(`[WebSocket Hub] Invalid client message:`, e.message);
        }
      });

      ws.on('close', () => {
        this.clients.delete(ws);
        console.log(`[WebSocket Hub] Client disconnected. Total active clients: ${this.clients.size}`);
      });

      ws.on('error', (err) => {
        console.warn(`[WebSocket Hub] Client error:`, err.message);
        this.clients.delete(ws);
      });
    });

    console.log(`[WebSocket Hub] WebSocket server operational on ${this.server ? 'HTTP server' : 'port ' + this.port}`);
  }

  broadcast(telemetryData) {
    if (this.clients.size === 0) return;

    const payload = JSON.stringify({
      type: 'TELEMETRY_UPDATE',
      data: telemetryData
    });

    for (const client of this.clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(payload);
      }
    }
  }

  stop() {
    if (this.wss) {
      this.wss.close();
    }
  }
}

module.exports = WebSocketServerHub;
