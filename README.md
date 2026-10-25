# FSTel - Farming Simulator 25 Telemetry & Virtual Button Box

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Farming Simulator 25](https://img.shields.io/badge/FS25-GIANTS%20Engine%2010-amber.svg)](https://www.farming-simulator.com/)
[![Node.js](https://img.shields.io/badge/Node.js-18%2B-blue.svg)](https://nodejs.org/)

**FSTel** is a high-performance telemetry streaming and bidirectional virtual button box ecosystem designed specifically for **Farming Simulator 25** (GIANTS Engine 10).

It brings real-time agricultural telemetry (speed, RPM, engine load, gears, fuel/AdBlue levels, hydraulics, PTO, tool folding, pipe position, fill units/tanks, and environmental data) to external tablets, smartphones, and secondary touch monitors with zero latency.

---

## 🏗️ Architecture

```
┌─────────────────────────────────┐
│ Farming Simulator 25            │
│ GIANTS Engine 10 (FS25_FSTel)   │
└───────────────┬─────────────────┘
                │ UDP Telemetry (30 Hz)
                ▼
┌─────────────────────────────────┐
│ Node.js PC Bridge Server        │
│ ├─ UDP Listener (Port 41234)    │
│ ├─ LAN Beacon (Port 41235)      │
│ ├─ WebSocket Hub (Port 8080)    │
│ ├─ HTTP Web Server (Port 3000)  │
│ └─ Windows SendInput Simulator  │
└───────┬─────────────────┬───────┘
        │                 │
        ▼                 ▼
┌──────────────┐   ┌──────────────┐
│ Web Terminal │   │ Android App  │
│ ISOBUS UI    │   │ Compose UI   │
└──────────────┘   └──────────────┘
```

---

## 🚀 Quick Start

### 1. Install the FS25 Mod
Run the packaging script to generate and deploy `FS25_FSTel.zip` directly to your game mods folder:
```powershell
powershell -ExecutionPolicy Bypass -File mod\package_mod.ps1
```
*Alternatively, copy `mod\FS25_FSTel.zip` manually into:*
`Documents\My Games\FarmingSimulator2025\mods\`

In FS25, enable **FSTel Telemetry & Virtual Button Box** in your savegame mod list.

### 2. Start the PC Bridge Server
```bash
cd server
npm install
npm start
```
The server will output:
- **Web Terminal**: `http://localhost:3000`
- **LAN Access**: `http://<YOUR_LOCAL_IP>:3000` (open this on your tablet or smartphone)
- **Built-in Demo Simulation**: Runs automatically when FS25 is not actively streaming so you can preview the terminal anytime!

---

## 🕹️ Virtual Button Box Mappings

| Control Button | Action | Default FS25 Key |
| :--- | :--- | :--- |
| **ENGINE** | Start / Stop Tractor Motor | `[ENTER]` |
| **CRUISE** | Toggle Cruise Control | `[3]` |
| **CRUISE - / +** | Adjust Target Speed | `[1]` / `[2]` |
| **PARK BRAKE** | Handbrake Toggle | `[SPACE]` |
| **HYDRAULICS** | Lower / Lift Primary Tool | `[V]` |
| **LIFT ALL** | Lower / Lift All Implements | `[CTRL + V]` |
| **PTO POWER** | Engage / Disengage PTO | `[B]` |
| **PTO ALL** | Engage All Tools | `[CTRL + B]` |
| **FOLD / UNFOLD** | Cycle Implement Wings | `[X]` |
| **UNLOAD PIPE** | Open / Close Pipe | `[O]` |
| **SWITCH TOOL** | Cycle Active Implement | `[G]` |
| **BEACONS** | Amber Warning Beacons | `[HOME]` |
| **LIGHTS** | Cycle Work/Headlights | `[F]` |
| **GPS** | Guidance Steering Mod | `[ALT + C]` |

---

## 📱 Features

- **ISOBUS-Style Rugged Cockpit UI**: Designed with high-luminance active SMD LEDs, brushed metal panels, and tactile physical depress feedback.
- **Dynamic Implement Monitoring**: Real-time fill levels for seeds, fertilizers, grain, herbicide, and slurry tanks with interactive progress bars.
- **Zero-Configuration LAN Auto-Discovery**: Android and web clients automatically discover the PC bridge on port `41235`.
- **Low Latency & High Reliability**: Native UDP socket streaming in Lua with pure-Lua JSON serialization and `pcall` failure protection.
