const fs = require('fs');

class FileTelemetryListener {
  constructor({ paths = [], intervalMs = 35, onTelemetryUpdate = null }) {
    this.paths = paths;
    this.intervalMs = intervalMs;
    this.onTelemetryUpdate = onTelemetryUpdate;
    this.intervalId = null;
    this.lastPacketTime = 0;
    this.lastRaw = '';
    this.lastSeq = -1;
    this.latestTelemetry = null;
    this.packetCount = 0;
    this.currentHz = 0;

    setInterval(() => {
      this.currentHz = this.packetCount;
      this.packetCount = 0;
    }, 1000);
  }

  start() {
    this.intervalId = setInterval(() => {
      this.poll();
    }, this.intervalMs);
    console.log(`[File Telemetry Listener] Active watching: ${this.paths.join(', ')}`);
  }

  poll() {
    for (const targetPath of this.paths) {
      if (!fs.existsSync(targetPath)) continue;

      try {
        const raw = fs.readFileSync(targetPath, 'utf8').trim();
        if (!raw || raw.length < 5 || raw === this.lastRaw) continue;
        this.lastRaw = raw;

        let data = null;
        if (raw.startsWith('{')) {
          data = JSON.parse(raw);
        } else if (raw.includes('payload="')) {
          const match = raw.match(/payload="([^"]+)"/);
          if (match && match[1]) {
            const unescaped = match[1]
              .replace(/&quot;/g, '"')
              .replace(/&amp;/g, '&')
              .replace(/&lt;/g, '<')
              .replace(/&gt;/g, '>');
            data = JSON.parse(unescaped);
          }
        }

        if (data && (data.inGame || data.vehicle) && data.seq !== this.lastSeq) {
          this.lastSeq = data.seq;
          this.lastPacketTime = Date.now();
          this.packetCount++;
          data._receivedAt = this.lastPacketTime;
          data._isDemo = false;
          this.latestTelemetry = data;

          if (typeof this.onTelemetryUpdate === 'function') {
            this.onTelemetryUpdate(data);
          }
          break;
        }
      } catch (err) {
        // File write concurrency, ignore
      }
    }
  }

  hasRecentData(maxAgeMs = 2500) {
    return (Date.now() - this.lastPacketTime) < maxAgeMs;
  }

  stop() {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }
}

module.exports = FileTelemetryListener;
