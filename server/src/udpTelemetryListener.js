const dgram = require('dgram');

class UdpTelemetryListener {
  constructor(port = 41234, onTelemetryUpdate = null) {
    this.port = port;
    this.onTelemetryUpdate = onTelemetryUpdate;
    this.socket = null;
    this.lastPacketTime = 0;
    this.packetCount = 0;
    this.currentHz = 0;
    this.latestTelemetry = null;
    this.isListening = false;

    // Calculate incoming Hz every second
    setInterval(() => {
      this.currentHz = this.packetCount;
      this.packetCount = 0;
    }, 1000);
  }

  start() {
    return new Promise((resolve, reject) => {
      this.socket = dgram.createSocket('udp4');

      this.socket.on('error', (err) => {
        console.error(`[UDP Listener] Socket error:`, err);
        reject(err);
      });

      this.socket.on('message', (msg, rinfo) => {
        try {
          const raw = msg.toString('utf8');
          const data = JSON.parse(raw);
          this.packetCount++;
          this.lastPacketTime = Date.now();
          data._receivedAt = this.lastPacketTime;
          data._source = `${rinfo.address}:${rinfo.port}`;
          this.latestTelemetry = data;

          if (typeof this.onTelemetryUpdate === 'function') {
            this.onTelemetryUpdate(data);
          }
        } catch (e) {
          console.warn(`[UDP Listener] Failed to parse JSON packet:`, e.message);
        }
      });

      this.socket.on('listening', () => {
        const address = this.socket.address();
        this.isListening = true;
        console.log(`[UDP Listener] In-game telemetry listening on 127.0.0.1:${address.port}`);
        resolve();
      });

      this.socket.bind(this.port, '127.0.0.1');
    });
  }

  hasRecentData(maxAgeMs = 2500) {
    return (Date.now() - this.lastPacketTime) < maxAgeMs;
  }

  stop() {
    if (this.socket) {
      this.socket.close();
      this.isListening = false;
    }
  }
}

module.exports = UdpTelemetryListener;
