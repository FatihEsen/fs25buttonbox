const { spawn } = require('child_process');

class InputSimulator {
  constructor() {
    this.keyMap = {
      // Vehicle Driving & Engine
      'ENGINE_START': '{ENTER}',
      'CRUISE_TOGGLE': '3',
      'CRUISE_SPEED_UP': '2',
      'CRUISE_SPEED_DOWN': '1',
      'HANDBRAKE': ' ',

      // Lights & Beacons
      'LIGHTS_CYCLE': 'f',
      'LIGHTS_BEACON': '{HOME}',
      'LIGHTS_WORK_FRONT': '{NUMPAD5}',
      'LIGHTS_WORK_BACK': '{NUMPAD6}',
      'LIGHTS_HAZARD': '---HAZARD---',

      // Implements & Attachments
      'TOOL_LOWER': 'v',
      'TOOL_LOWER_ALL': '^v', // Ctrl + V
      'TOOL_PTO': 'b',
      'TOOL_PTO_ALL': '^b', // Ctrl + B
      'TOOL_FOLD': 'x',
      'PIPE_TOGGLE': 'o',
      'TOOL_SELECT': 'g',

      // AI Helper / Worker
      'AI_WORKER': 'h',
      'TOGGLE_AI': 'h',

      // GPS / Guidance Steering Mod
      'GPS_TOGGLE': '%c' // Alt + C
    };

    this.lastTriggerTime = {};
  }

  triggerAction(actionName) {
    const key = this.keyMap[actionName];
    if (!key) {
      console.warn(`[Input Simulator] Unknown action: ${actionName}`);
      return false;
    }

    const now = Date.now();
    const last = this.lastTriggerTime[actionName] || 0;
    // Debounce 100ms
    if (now - last < 100) {
      return false;
    }
    this.lastTriggerTime[actionName] = now;

    console.log(`[Input Simulator] Emulating action: ${actionName} -> [${key}]`);

    if (process.platform === 'win32') {
      this.sendWindowsKey(key, actionName);
    } else {
      console.log(`[Input Simulator] Platform ${process.platform}: Key simulation simulated in log.`);
    }

    return true;
  }

  sendWindowsKey(keyPattern, actionName) {
    let script = '';
    if (keyPattern === '---HAZARD---') {
      // Hazard is usually comma (,) or dedicated key in mods
      script = `[System.Windows.Forms.SendKeys]::SendWait(',')`;
    } else {
      // Escape for single quotes in PowerShell
      const escaped = keyPattern.replace(/'/g, "''");
      script = `[System.Windows.Forms.SendKeys]::SendWait('${escaped}')`;
    }

    const psCommand = `Add-Type -AssemblyName System.Windows.Forms; ${script}`;

    const child = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', psCommand], {
      windowsHide: true
    });

    child.on('error', (err) => {
      console.warn(`[Input Simulator] Error executing key press:`, err.message);
    });
  }
}

module.exports = InputSimulator;
