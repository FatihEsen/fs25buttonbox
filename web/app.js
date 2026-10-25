/**
 * FSTel - ISOBUS Agricultural Terminal & Virtual Button Box Controller
 * Real-time bidirectional WebSocket telemetry & tactile input dispatcher
 */

(function () {
  'use strict';

  // State Management
  const state = {
    connected: false,
    useMph: false,
    audioEnabled: true,
    activeTab: 'dashboard',
    lastTelemetry: null,
    ws: null,
    reconnectTimer: null,
    activeActions: new Set()
  };

  // Audio Click Synthesizer (Instant low-latency Web Audio API)
  let audioCtx = null;
  function playClickFeedback(isRelease = false) {
    if (!state.audioEnabled) return;

    // Haptic vibration on supported devices (tablets/phones)
    if (navigator.vibrate) {
      navigator.vibrate(isRelease ? 10 : 25);
    }

    try {
      if (!audioCtx) {
        audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      }
      if (audioCtx.state === 'suspended') {
        audioCtx.resume();
      }

      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();
      osc.type = isRelease ? 'sine' : 'triangle';
      osc.frequency.setValueAtTime(isRelease ? 440 : 680, audioCtx.currentTime);
      osc.frequency.exponentialRampToValueAtTime(isRelease ? 220 : 120, audioCtx.currentTime + 0.04);

      gain.gain.setValueAtTime(0.15, audioCtx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.04);

      osc.connect(gain);
      gain.connect(audioCtx.destination);
      osc.start();
      osc.stop(audioCtx.currentTime + 0.04);
    } catch (e) {
      // Audio element fallback
      const audioElem = document.getElementById('clickSound');
      if (audioElem) {
        audioElem.currentTime = 0;
        audioElem.play().catch(() => {});
      }
    }
  }

  // DOM Elements Cache
  const els = {
    connectionStatus: document.getElementById('connectionStatus'),
    connectionText: document.getElementById('connectionText'),
    vehicleName: document.getElementById('vehicleName'),
    vehicleCategory: document.getElementById('vehicleCategory'),
    envClock: document.getElementById('envClock'),
    envWeatherIcon: document.getElementById('envWeatherIcon'),
    envTemp: document.getElementById('envTemp'),
    envMoney: document.getElementById('envMoney'),
    btnAudioToggle: document.getElementById('btnAudioToggle'),
    btnFullscreen: document.getElementById('btnFullscreen'),
    btnSpeedUnitToggle: document.getElementById('btnSpeedUnitToggle'),
    speedValue: document.getElementById('speedValue'),
    speedUnit: document.getElementById('speedUnit'),
    speedArcProgress: document.getElementById('speedArcProgress'),
    gearValue: document.getElementById('gearValue'),
    cruiseTarget: document.getElementById('cruiseTarget'),
    operatingHours: document.getElementById('operatingHours'),
    rpmValue: document.getElementById('rpmValue'),
    rpmBar: document.getElementById('rpmBar'),
    loadValue: document.getElementById('loadValue'),
    loadBar: document.getElementById('loadBar'),
    fuelText: document.getElementById('fuelText'),
    fuelBar: document.getElementById('fuelBar'),
    defText: document.getElementById('defText'),
    defBar: document.getElementById('defBar'),
    activeToolName: document.getElementById('activeToolName'),
    toolPositionBadge: document.getElementById('toolPositionBadge'),
    toolPtoBadge: document.getElementById('toolPtoBadge'),
    toolFoldBadge: document.getElementById('toolFoldBadge'),
    toolPipeBadge: document.getElementById('toolPipeBadge'),
    fillUnitsContainer: document.getElementById('fillUnitsContainer'),
    implementSlotsList: document.getElementById('implementSlotsList'),
    fullImplementsGrid: document.getElementById('fullImplementsGrid'),
    setServerStatus: document.getElementById('setServerStatus'),
    setGameStreamStatus: document.getElementById('setGameStreamStatus'),
    setStreamHz: document.getElementById('setStreamHz'),
    btnToggleDemoMode: document.getElementById('btnToggleDemoMode'),
    btnSendTestPing: document.getElementById('btnSendTestPing'),

    // Dash Indicators
    indBeacon: document.getElementById('indBeacon'),
    indLowBeam: document.getElementById('indLowBeam'),
    indHighBeam: document.getElementById('indHighBeam'),
    indWorkFront: document.getElementById('indWorkFront'),
    indWorkRear: document.getElementById('indWorkRear'),
    indHazard: document.getElementById('indHazard'),
    indDiffLock: document.getElementById('indDiffLock'),
    indHandbrake: document.getElementById('indHandbrake'),

    // Views
    tabs: document.querySelectorAll('.tab-btn'),
    viewPanels: {
      dashboard: document.getElementById('viewDashboard'),
      buttonbox: document.getElementById('viewButtonBox'),
      settings: document.getElementById('viewSettings')
    }
  };

  // Setup WebSocket Connection
  function initWebSocket() {
    const host = window.location.hostname || 'localhost';
    const wsPort = 8080;
    const wsUrl = `ws://${host}:${wsPort}`;

    console.log(`[FSTel Client] Connecting to WebSocket: ${wsUrl}`);
    updateConnectionStatus('connecting', 'CONNECTING...');

    try {
      state.ws = new WebSocket(wsUrl);

      state.ws.onopen = () => {
        console.log('[FSTel Client] WebSocket connected successfully');
        state.connected = true;
        updateConnectionStatus('connected', 'CONNECTED (ONLINE)');
        if (els.setServerStatus) {
          els.setServerStatus.textContent = `ONLINE (WebSocket ${wsPort})`;
          els.setServerStatus.className = 'set-val accent-green';
        }
      };

      state.ws.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data);
          if (msg.type === 'TELEMETRY_UPDATE' && msg.data) {
            handleTelemetryUpdate(msg.data);
          } else if (msg.type === 'PONG') {
            const rtt = Date.now() - msg.clientTime;
            alert(`FSTel Bridge Latency: ${rtt} ms`);
          }
        } catch (e) {
          console.warn('[FSTel Client] Failed to parse incoming packet:', e);
        }
      };

      state.ws.onclose = () => {
        console.warn('[FSTel Client] WebSocket disconnected. Retrying in 2.5s...');
        state.connected = false;
        updateConnectionStatus('disconnected', 'DISCONNECTED (RECONNECTING...)');
        if (els.setServerStatus) {
          els.setServerStatus.textContent = 'DISCONNECTED';
          els.setServerStatus.className = 'set-val accent-amber';
        }
        scheduleReconnect();
      };

      state.ws.onerror = (err) => {
        console.error('[FSTel Client] WebSocket error:', err);
        state.ws.close();
      };
    } catch (err) {
      console.error('[FSTel Client] Initialization exception:', err);
      scheduleReconnect();
    }
  }

  function scheduleReconnect() {
    if (state.reconnectTimer) clearTimeout(state.reconnectTimer);
    state.reconnectTimer = setTimeout(() => {
      initWebSocket();
    }, 2500);
  }

  function updateConnectionStatus(mode, text) {
    if (!els.connectionStatus || !els.connectionText) return;
    els.connectionStatus.className = 'status-pill';
    if (mode === 'connected') {
      els.connectionStatus.classList.add('status-connected');
    } else if (mode === 'demo') {
      els.connectionStatus.classList.add('status-demo');
    } else {
      els.connectionStatus.classList.add('status-disconnected');
    }
    els.connectionText.textContent = text;
  }

  // Dispatch Action to PC Bridge
  function dispatchAction(actionName) {
    console.log(`[FSTel Client] Trigger action: ${actionName}`);
    playClickFeedback(false);

    // Send over WebSocket if open
    if (state.ws && state.ws.readyState === WebSocket.OPEN) {
      state.ws.send(JSON.stringify({
        type: 'BUTTON_ACTION',
        action: actionName,
        timestamp: Date.now()
      }));
    } else {
      // Fallback: HTTP REST POST
      fetch('/api/action', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: actionName })
      }).catch(err => console.warn('HTTP Action fallback error:', err));
    }
  }

  // Update UI Elements with Incoming Telemetry
  function handleTelemetryUpdate(telemetry) {
    state.lastTelemetry = telemetry;

    const isDemo = telemetry._isDemo === true;
    updateConnectionStatus(isDemo ? 'demo' : 'connected', isDemo ? 'CONNECTED (DEMO SIM)' : 'LIVE (FS25 IN-GAME)');

    if (els.setGameStreamStatus) {
      els.setGameStreamStatus.textContent = isDemo ? 'DEMO GENERATOR (FS25 Not Detected)' : 'ACTIVE IN-GAME STREAM';
      els.setGameStreamStatus.className = isDemo ? 'set-val accent-amber' : 'set-val accent-green';
    }

    const veh = telemetry.vehicle;
    if (!veh) return;

    // Vehicle Name & Category
    if (els.vehicleName) els.vehicleName.textContent = veh.name || 'Universal Machine';
    if (els.vehicleCategory) els.vehicleCategory.textContent = (veh.typeName || 'TRACTOR').toUpperCase();

    // Speed Gauge (KM/H or MPH)
    const speed = state.useMph ? (veh.speedMph || 0) : (veh.speedKmh || 0);
    if (els.speedValue) els.speedValue.textContent = speed.toFixed(1);
    if (els.speedUnit) els.speedUnit.textContent = state.useMph ? 'MPH' : 'KM/H';
    if (els.btnSpeedUnitToggle) els.btnSpeedUnitToggle.textContent = state.useMph ? 'MPH' : 'KM/H';

    // SVG Speed Gauge Arc Calculation (Max speed ~65 km/h for gauge)
    if (els.speedArcProgress) {
      const maxGaugeSpeed = state.useMph ? 40 : 65;
      const pct = Math.min(1, Math.max(0, speed / maxGaugeSpeed));
      const totalArcLength = 251.2;
      const offset = totalArcLength * (1 - pct);
      els.speedArcProgress.style.strokeDashoffset = offset;
    }

    // Gear, Cruise Target & Hours
    if (els.gearValue) {
      els.gearValue.textContent = veh.gearName || veh.gear || 'D';
    }
    if (els.cruiseTarget && veh.cruiseControl) {
      const cruiseSpeed = state.useMph 
        ? Math.round((veh.cruiseControl.targetSpeed || 0) * 0.621371) 
        : Math.round(veh.cruiseControl.targetSpeed || 0);
      els.cruiseTarget.textContent = `${cruiseSpeed} ${state.useMph ? 'MPH' : 'KM/H'}`;
    }
    if (els.operatingHours) {
      els.operatingHours.textContent = `${(veh.operatingHours || 0).toFixed(1)} h`;
    }

    // Engine RPM & Motor Load
    if (els.rpmValue) {
      els.rpmValue.textContent = `${(veh.rpm || 0).toLocaleString()} RPM`;
    }
    if (els.rpmBar) {
      const minRpm = veh.minRpm || 800;
      const maxRpm = veh.maxRpm || 2400;
      const rpmPct = Math.min(100, Math.max(0, (((veh.rpm || 0) - minRpm) / (maxRpm - minRpm)) * 100));
      els.rpmBar.style.width = `${rpmPct.toFixed(1)}%`;
    }

    if (els.loadValue) {
      els.loadValue.textContent = `${Math.round(veh.motorLoadPercent || 0)}%`;
    }
    if (els.loadBar) {
      els.loadBar.style.width = `${Math.min(100, Math.max(0, veh.motorLoadPercent || 0))}%`;
    }

    // Fuel & DEF
    if (veh.fuel) {
      if (els.fuelText) els.fuelText.textContent = `${Math.round(veh.fuel.fillLevel || 0)} / ${Math.round(veh.fuel.capacity || 0)} L`;
      if (els.fuelBar) els.fuelBar.style.width = `${Math.min(100, Math.max(0, veh.fuel.fillPercent || 0))}%`;
    }
    if (veh.def) {
      if (els.defText) els.defText.textContent = `${Math.round(veh.def.fillLevel || 0)} / ${Math.round(veh.def.capacity || 0)} L`;
      if (els.defBar) els.defBar.style.width = `${Math.min(100, Math.max(0, veh.def.fillPercent || 0))}%`;
    }

    // Dashboard Indicators
    if (veh.lights) {
      toggleActive(els.indBeacon, veh.lights.beaconActive);
      toggleActive(els.indLowBeam, veh.lights.lowBeam);
      toggleActive(els.indHighBeam, veh.lights.highBeam);
      toggleActive(els.indWorkFront, veh.lights.workLightsFront);
      toggleActive(els.indWorkRear, veh.lights.workLightsBack);
      toggleActive(els.indHazard, veh.lights.turnLightState === 3);
    }
    if (veh.drivetrain) {
      toggleActive(els.indDiffLock, veh.drivetrain.diffLockRear || veh.drivetrain.diffLockFront);
      toggleActive(els.indHandbrake, veh.drivetrain.handbrake);
    }

    // Synchronize Virtual Buttons State LED
    syncButtonStates(veh);

    // Environment Data
    if (telemetry.environment) {
      const env = telemetry.environment;
      if (els.envClock) els.envClock.textContent = env.clock || '--:--';
      if (els.envTemp) els.envTemp.textContent = `${env.temperature || 20}°C`;
      if (els.envMoney) els.envMoney.textContent = `€ ${(env.money || 0).toLocaleString()}`;

      if (els.envWeatherIcon) {
        const weather = (env.weather || 'SUNNY').toUpperCase();
        if (weather.includes('RAIN')) els.envWeatherIcon.textContent = '🌧️';
        else if (weather.includes('CLOUD')) els.envWeatherIcon.textContent = '☁️';
        else if (weather.includes('SNOW')) els.envWeatherIcon.textContent = '❄️';
        else els.envWeatherIcon.textContent = '☀️';
      }
    }

    // Attached Implements & Fill Units
    renderImplements(veh.implements || []);
  }

  function toggleActive(elem, isActive) {
    if (!elem) return;
    if (isActive) {
      elem.classList.add('active');
    } else {
      elem.classList.remove('active');
    }
  }

  function syncButtonStates(veh) {
    // Engine buttons (Matrix & any other)
    document.querySelectorAll('.btn-engine, #btnEngine').forEach(el => {
      el.classList.toggle('active-state', !!veh.isEngineStarted);
    });

    // Cruise buttons
    document.querySelectorAll('.btn-cruise, #btnCruiseToggle').forEach(el => {
      el.classList.toggle('active-state', !!(veh.cruiseControl && veh.cruiseControl.isActive));
    });

    // Beacon buttons
    document.querySelectorAll('.btn-beacon, #btnBeacon').forEach(el => {
      el.classList.toggle('active-state', !!(veh.lights && veh.lights.beaconActive));
    });

    // Primary tool status
    const primaryTool = (veh.implements || []).find(i => i.isSelected) || (veh.implements && veh.implements[0]);
    if (primaryTool) {
      document.querySelectorAll('.btn-hydraulics, #btnToolLower').forEach(el => {
        el.classList.toggle('active-state', !!primaryTool.isLowered);
      });
      document.querySelectorAll('.btn-pto, #btnToolPto').forEach(el => {
        el.classList.toggle('active-state', !!primaryTool.isTurnedOn);
      });
      document.querySelectorAll('.btn-fold, #btnToolFold').forEach(el => {
        el.classList.toggle('active-state', !!primaryTool.isFolded);
      });
      document.querySelectorAll('.btn-pipe, #btnPipe').forEach(el => {
        el.classList.toggle('active-state', !!primaryTool.pipeDischarging);
      });
    }
  }

  // Render Attached Implements & Tanks
  function renderImplements(implementsList) {
    const primaryTool = implementsList.find(i => i.isSelected) || implementsList[0];

    // Primary Tool Card Header
    if (primaryTool) {
      if (els.activeToolName) els.activeToolName.textContent = primaryTool.name || 'Implement';

      const toolSub = document.getElementById('activeToolSub');
      if (toolSub) toolSub.textContent = primaryTool.typeName || 'Universal Implement';

      const schematicTool = document.getElementById('schematicToolName');
      if (schematicTool) schematicTool.textContent = `🌾 ${(primaryTool.name || 'IMPLEMENT').toUpperCase()}`;

      if (els.toolPositionBadge) {
        els.toolPositionBadge.textContent = primaryTool.isLowered ? 'LOWERED' : 'LIFTED';
        els.toolPositionBadge.className = `badge ${primaryTool.isLowered ? 'badge-lowered' : 'badge-lifted'}`;
      }

      if (els.toolPtoBadge) {
        els.toolPtoBadge.textContent = primaryTool.isTurnedOn ? 'PTO: ENGAGED' : 'PTO: IDLE';
        els.toolPtoBadge.className = `status-tag ${primaryTool.isTurnedOn ? 'tag-pto-on' : ''}`;
      }

      if (els.toolFoldBadge) {
        els.toolFoldBadge.textContent = primaryTool.isFolded ? 'FOLDED (TRANSPORT)' : 'UNFOLDED (WORK)';
        els.toolFoldBadge.className = `status-tag ${!primaryTool.isFolded ? 'tag-unfolded' : ''}`;
      }

      if (els.toolPipeBadge) {
        els.toolPipeBadge.textContent = primaryTool.pipeDischarging ? 'PIPE: ACTIVE' : 'PIPE: RETRACTED';
        els.toolPipeBadge.className = `status-tag ${primaryTool.pipeDischarging ? 'tag-pipe-open' : ''}`;
      }

      // Fill Units for Primary Tool
      if (els.fillUnitsContainer) {
        renderTanks(els.fillUnitsContainer, primaryTool.fillUnits || []);
      }
    } else {
      if (els.activeToolName) els.activeToolName.textContent = 'NO IMPLEMENT ATTACHED';
      const toolSub = document.getElementById('activeToolSub');
      if (toolSub) toolSub.textContent = 'Ready for connection';
      if (els.fillUnitsContainer) els.fillUnitsContainer.innerHTML = '<div style="color:var(--text-dim);font-size:0.8rem;padding:8px;">No material containers detected.</div>';
    }

    // Unified Equipment Slots Bar (Interactive Sleek Pills)
    if (els.implementSlotsList) {
      els.implementSlotsList.innerHTML = '';
      if (implementsList.length === 0) {
        els.implementSlotsList.innerHTML = '<div style="color:var(--text-dim);font-size:0.75rem;padding:4px 8px;">No implements attached</div>';
      } else {
        implementsList.forEach((tool, idx) => {
          const pill = document.createElement('button');
          pill.className = `slot-pill ${tool.isSelected ? 'slot-active' : ''}`;
          pill.title = `Switch to ${tool.name} [G]`;
          pill.innerHTML = `
            <span class="slot-pill-badge">SLOT #${idx + 1}</span>
            <div class="slot-pill-info">
              <span class="slot-pill-name">${tool.name}</span>
              <span class="slot-pill-status">${tool.isTurnedOn ? '⚡ RUNNING' : (tool.isSelected ? 'ACTIVE' : 'IDLE')}</span>
            </div>
          `;
          pill.addEventListener('click', () => {
            dispatchAction('TOOL_SELECT');
          });
          els.implementSlotsList.appendChild(pill);
        });
      }
    }
  }

  function renderTanks(container, fillUnits) {
    container.innerHTML = '';
    if (!fillUnits || fillUnits.length === 0) {
      container.innerHTML = '<span style="color:var(--text-dim);font-size:0.75rem;">No storage tanks.</span>';
      return;
    }

    fillUnits.forEach((unit) => {
      const type = (unit.fillTypeName || 'MATERIAL').toUpperCase();
      let icon = '📦';
      let fillClass = 'tank-fill-seeds';

      if (type.includes('SEED')) {
        icon = '🌱';
        fillClass = 'tank-fill-seeds';
      } else if (type.includes('FERTILIZER') || type.includes('LIME')) {
        icon = '🧪';
        fillClass = 'tank-fill-fert';
      } else if (type.includes('WHEAT') || type.includes('BARLEY') || type.includes('CORN') || type.includes('CANOLA')) {
        icon = '🌾';
        fillClass = 'tank-fill-grain';
      } else if (type.includes('SLURRY') || type.includes('WATER') || type.includes('MILK')) {
        icon = '💧';
        fillClass = 'tank-fill-fert';
      }

      const card = document.createElement('div');
      card.className = 'fill-tank-card';
      card.innerHTML = `
        <div class="tank-meta">
          <span class="tank-title">${icon} ${type}</span>
          <span class="tank-percent">${(unit.fillPercent || 0).toFixed(1)}%</span>
        </div>
        <div class="bar-track tank-track">
          <div class="bar-fill ${fillClass}" style="width: ${Math.min(100, unit.fillPercent || 0)}%;"></div>
        </div>
        <div class="tank-volume">${Math.round(unit.fillLevel || 0).toLocaleString()} / ${Math.round(unit.capacity || 0).toLocaleString()} L</div>
      `;
      container.appendChild(card);
    });
  }

  // Setup Event Listeners
  function setupEvents() {
    // Tab Switching
    els.tabs.forEach((tabBtn) => {
      tabBtn.addEventListener('click', () => {
        const tabId = tabBtn.getAttribute('data-tab');
        if (!tabId || !els.viewPanels[tabId]) return;

        els.tabs.forEach(t => t.classList.remove('active'));
        tabBtn.classList.add('active');

        Object.keys(els.viewPanels).forEach((key) => {
          els.viewPanels[key].classList.toggle('active-panel', key === tabId);
        });
        state.activeTab = tabId;
        playClickFeedback(true);
      });
    });

    // Tactile Buttons Touch & Click Binding (Smooth Mobile Scrolling Friendly)
    const tactileButtons = document.querySelectorAll('.tactile-btn');
    tactileButtons.forEach((btn) => {
      const action = btn.getAttribute('data-action');
      if (!action) return;

      // Desktop Mouse Clicks
      btn.addEventListener('mousedown', (e) => {
        btn.classList.add('pressed');
        dispatchAction(action);
      });

      const onMouseUp = () => {
        btn.classList.remove('pressed');
      };
      btn.addEventListener('mouseup', onMouseUp);
      btn.addEventListener('mouseleave', onMouseUp);

      // Mobile Touch: Allows scrolling without accidental triggers
      let touchStartX = 0;
      let touchStartY = 0;
      let isTouchScrolling = false;

      btn.addEventListener('touchstart', (e) => {
        if (!e.touches || e.touches.length === 0) return;
        touchStartX = e.touches[0].clientX;
        touchStartY = e.touches[0].clientY;
        isTouchScrolling = false;
        btn.classList.add('pressed');
      }, { passive: true });

      btn.addEventListener('touchmove', (e) => {
        if (!e.touches || e.touches.length === 0) return;
        const deltaX = Math.abs(e.touches[0].clientX - touchStartX);
        const deltaY = Math.abs(e.touches[0].clientY - touchStartY);
        // If finger moves more than 8 pixels, user is scrolling the page
        if (deltaX > 8 || deltaY > 8) {
          isTouchScrolling = true;
          btn.classList.remove('pressed');
        }
      }, { passive: true });

      btn.addEventListener('touchend', (e) => {
        btn.classList.remove('pressed');
        if (!isTouchScrolling) {
          // Genuine tap: trigger action
          dispatchAction(action);
        }
      });

      btn.addEventListener('touchcancel', () => {
        btn.classList.remove('pressed');
        isTouchScrolling = true;
      });
    });

    // Speed Unit Toggle
    if (els.btnSpeedUnitToggle) {
      els.btnSpeedUnitToggle.addEventListener('click', () => {
        state.useMph = !state.useMph;
        els.btnSpeedUnitToggle.textContent = state.useMph ? 'MPH' : 'KM/H';
        playClickFeedback(true);
        if (state.lastTelemetry) handleTelemetryUpdate(state.lastTelemetry);
      });
    }

    // Audio Toggle
    if (els.btnAudioToggle) {
      els.btnAudioToggle.addEventListener('click', () => {
        state.audioEnabled = !state.audioEnabled;
        els.btnAudioToggle.querySelector('.icon').textContent = state.audioEnabled ? '🔊' : '🔇';
        playClickFeedback(true);
      });
    }

    // Fullscreen Toggle
    if (els.btnFullscreen) {
      els.btnFullscreen.addEventListener('click', () => {
        if (!document.fullscreenElement) {
          document.documentElement.requestFullscreen().catch(() => {});
        } else {
          document.exitFullscreen().catch(() => {});
        }
        playClickFeedback(true);
      });
    }

    // Settings Actions
    if (els.btnToggleDemoMode) {
      els.btnToggleDemoMode.addEventListener('click', () => {
        fetch('/api/demo/toggle', { method: 'POST' })
          .then(res => res.json())
          .then(data => {
            alert(`Demo Mode is now: ${data.demoMode ? 'ENABLED' : 'DISABLED'}`);
          });
      });
    }

    if (els.btnSendTestPing) {
      els.btnSendTestPing.addEventListener('click', () => {
        if (state.ws && state.ws.readyState === WebSocket.OPEN) {
          state.ws.send(JSON.stringify({ type: 'PING', timestamp: Date.now() }));
        } else {
          alert('WebSocket not connected.');
        }
      });
    }
  }

  // Initialization
  document.addEventListener('DOMContentLoaded', () => {
    setupEvents();
    initWebSocket();
  });
})();
