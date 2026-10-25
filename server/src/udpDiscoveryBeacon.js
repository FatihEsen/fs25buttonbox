const dgram = require('dgram');
const os = require('os');

class UdpDiscoveryBeacon {
  constructor({ broadcastPort = 41235, httpPort = 3000, wsPort = 8080 }) {
    this.broadcastPort = broadcastPort;
    this.httpPort = httpPort;
    this.wsPort = wsPort;
    this.socket = null;
    this.intervalId = null;
  }

  getLocalIpAddresses() {
    const interfaces = os.networkInterfaces();
    const ips = [];
    for (const name of Object.keys(interfaces)) {
      for (const net of interfaces[name]) {
        // Skip over non-IPv4 and internal (i.e. 127.0.0.1) addresses
        if (net.family === 'IPv4' && !net.internal) {
          ips.push({ name, address: net.address });
        }
      }
    }
    return ips;
  }

  start() {
    this.socket = dgram.createSocket({ type: 'udp4', reuseAddr: true });

    this.socket.on('error', (err) => {
      console.warn(`[Discovery Beacon] Socket error:`, err.message);
    });

    this.socket.on('message', (msg, rinfo) => {
      try {
        const query = JSON.parse(msg.toString('utf8'));
        if (query.type === 'FSTEL_DISCOVER_QUERY') {
          // Direct response to inquiring client
          this.sendBeacon(rinfo.address, rinfo.port);
        }
      } catch (_) {}
    });

    this.socket.bind(this.broadcastPort, () => {
      try {
        this.socket.setBroadcast(true);
      } catch (e) {
        console.warn(`[Discovery Beacon] Could not set broadcast flag:`, e.message);
      }
      console.log(`[Discovery Beacon] Auto-discovery active on UDP port ${this.broadcastPort}`);

      // Broadcast every 2 seconds
      this.intervalId = setInterval(() => {
        this.sendBeacon('255.255.255.255', this.broadcastPort);
      }, 2000);
    });
  }

  sendBeacon(targetIp, targetPort) {
    if (!this.socket) return;
    const ips = this.getLocalIpAddresses();
    const primaryIp = ips.length > 0 ? ips[0].address : '127.0.0.1';

    const payload = JSON.stringify({
      type: 'FSTEL_BEACON',
      serverName: os.hostname(),
      serverIp: primaryIp,
      allIps: ips.map((i) => i.address),
      httpPort: this.httpPort,
      wsPort: this.wsPort,
      timestamp: Date.now(),
      version: '1.0.0'
    });

    const buffer = Buffer.from(payload);
    this.socket.send(buffer, 0, buffer.length, targetPort, targetIp, (err) => {
      if (err && err.code !== 'ENETUNREACH') {
        // Silently ignore unreachable network broadcasts
      }
    });
  }

  stop() {
    if (this.intervalId) clearInterval(this.intervalId);
    if (this.socket) {
      this.socket.close();
      this.socket = null;
    }
  }
}

module.exports = UdpDiscoveryBeacon;
