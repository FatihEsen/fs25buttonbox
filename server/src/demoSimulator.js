class DemoSimulator {
  constructor(onUpdate = null) {
    this.onUpdate = onUpdate;
    this.isRunning = false;
    this.intervalId = null;
    this.t = 0;

    this.state = {
      speed: 15.0,
      targetSpeed: 15.0,
      rpm: 1550,
      load: 64,
      fuel: 385,
      fuelCap: 500,
      def: 42,
      defCap: 50,
      hours: 124.6,
      beacon: true,
      workLights: true,
      highBeam: false,
      turnSignal: 0,
      toolLowered: true,
      ptoRunning: true,
      pipeOpen: false,
      wipers: false,
      belts: false,
      cover: false,
      aiActive: false,
      posX: 124.5,
      posZ: -340.2,
      heading: 45,
      seedsLevel: 4200,
      seedsCap: 5500,
      money: 184500
    };
  }

  start(hz = 25) {
    if (this.isRunning) return;
    this.isRunning = true;
    const intervalMs = Math.floor(1000 / hz);

    this.intervalId = setInterval(() => {
      this.tick();
    }, intervalMs);
  }

  stop() {
    this.isRunning = false;
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  tick() {
    this.t += 0.05;

    // Simulate undulating speed and RPM based on field terrain
    const speedVariation = Math.sin(this.t * 0.4) * 2.5;
    const currentSpeed = Math.max(0, 15.0 + speedVariation);
    const rpmVariation = Math.sin(this.t * 0.8) * 120 + (currentSpeed * 15);
    const currentRpm = Math.min(2100, Math.max(850, 1500 + rpmVariation));
    const currentLoad = Math.min(95, Math.max(35, 60 + Math.sin(this.t * 0.6) * 22));

    // Slowly consume seeds and fuel
    this.state.seedsLevel = Math.max(500, this.state.seedsLevel - 0.2);
    this.state.fuel = Math.max(10, this.state.fuel - 0.005);

    // Simulate vehicle movement on map (in meters)
    const dt = 0.04;
    const speedMs = (currentSpeed * 1000) / 3600;
    this.state.heading = (this.state.heading + Math.sin(this.t * 0.1) * 0.4 + 360) % 360;
    const rad = (this.state.heading * Math.PI) / 180;
    this.state.posX += Math.sin(rad) * speedMs * dt;
    this.state.posZ += Math.cos(rad) * speedMs * dt;

    const telemetry = {
      protocol: "FSTEL_1.0",
      seq: Math.floor(this.t * 20),
      timestamp: Date.now(),
      _isDemo: true,
      vehicle: {
        id: 101,
        name: "Fendt 942 Vario TMS",
        typeName: "tractor",
        isControlled: true,
        speedKmh: parseFloat(currentSpeed.toFixed(1)),
        speedMph: parseFloat((currentSpeed * 0.621371).toFixed(1)),
        gear: 2,
        gearName: "II",
        isAutomatic: true,
        isEngineStarted: true,
        rpm: Math.round(currentRpm),
        minRpm: 800,
        maxRpm: 2200,
        motorLoadPercent: parseFloat(currentLoad.toFixed(1)),
        operatingHours: this.state.hours,
        position: {
          x: parseFloat(this.state.posX.toFixed(1)),
          y: 84.2,
          z: parseFloat(this.state.posZ.toFixed(1)),
          heading: Math.round(this.state.heading)
        },
        cruiseControl: {
          isActive: true,
          targetSpeed: 15
        },
        fuel: {
          fillLevel: parseFloat(this.state.fuel.toFixed(1)),
          capacity: this.state.fuelCap,
          fillPercent: parseFloat(((this.state.fuel / this.state.fuelCap) * 100).toFixed(1))
        },
        def: {
          fillLevel: parseFloat(this.state.def.toFixed(1)),
          capacity: this.state.defCap,
          fillPercent: parseFloat(((this.state.def / this.state.defCap) * 100).toFixed(1))
        },
        lights: {
          beaconActive: this.state.beacon,
          turnLightState: this.state.turnSignal,
          highBeam: this.state.highBeam,
          lowBeam: true,
          workLightsFront: this.state.workLights,
          workLightsBack: this.state.workLights
        },
        drivetrain: {
          handbrake: false,
          allWheelDrive: true,
          diffLockFront: false,
          diffLockRear: true
        },
        tensionBeltsActive: !!this.state.belts,
        implements: [
          {
            index: 1,
            name: "Horsch Pronto 9 DC",
            isSelected: this.state.activeToolIndex === 1,
            isLowered: this.state.toolLowered,
            isTurnedOn: this.state.ptoRunning,
            isFolded: false,
            foldPercent: 100,
            pipeDischarging: false,
            fillUnits: [
              {
                unitIndex: 1,
                fillTypeName: "SEEDS",
                fillLevel: Math.round(this.state.seedsLevel),
                capacity: this.state.seedsCap,
                fillPercent: parseFloat(((this.state.seedsLevel / this.state.seedsCap) * 100).toFixed(1))
              },
              {
                unitIndex: 2,
                fillTypeName: "FERTILIZER",
                fillLevel: 1850,
                capacity: 2500,
                fillPercent: 74.0
              }
            ]
          },
          {
            index: 2,
            name: "Weight 1500kg",
            isSelected: this.state.activeToolIndex === 2,
            isLowered: false,
            isTurnedOn: false,
            isFolded: false,
            foldPercent: 0,
            pipeDischarging: false,
            fillUnits: []
          }
        ]
      },
      environment: {
        clock: "14:28",
        dayTimeMs: 52080000,
        day: 3,
        month: 4,
        temperature: 22,
        weather: "SUNNY",
        money: this.state.money,
        mapName: "Zielonka (FS25)",
        mapId: "mapEU",
        mapSize: 2048
      }
    };

    if (typeof this.onUpdate === 'function') {
      this.onUpdate(telemetry);
    }
  }

  handleAction(actionName) {
    if (actionName === 'LIGHTS_BEACON') this.state.beacon = !this.state.beacon;
    if (actionName === 'LIGHTS_HAZARD') this.state.turnSignal = (this.state.turnSignal === 3) ? 0 : 3;
    if (actionName === 'LIGHTS_CYCLE') {
      if (!this.state.highBeam && this.state.beacon) {
        this.state.highBeam = true;
      } else if (this.state.highBeam) {
        this.state.highBeam = false;
      } else {
        this.state.highBeam = true;
      }
    }
    if (actionName === 'LIGHTS_WORK_FRONT' || actionName === 'LIGHTS_WORK_BACK') {
      this.state.workLights = !this.state.workLights;
    }
    if (actionName === 'TOOL_LOWER' || actionName === 'TOOL_LOWER_ALL') this.state.toolLowered = !this.state.toolLowered;
    if (actionName === 'TOOL_PTO' || actionName === 'TOOL_PTO_ALL') this.state.ptoRunning = !this.state.ptoRunning;
    if (actionName === 'TOOL_SELECT') {
      this.state.activeToolIndex = (this.state.activeToolIndex === 1) ? 2 : 1;
    }
    if (actionName === 'PIPE_TOGGLE') this.state.pipeOpen = !this.state.pipeOpen;
    if (actionName === 'TOGGLE_TIPSIDE') this.state.tipSide = ((this.state.tipSide || 1) % 3) + 1;
    if (actionName === 'TOGGLE_TENSION_BELTS') this.state.belts = !this.state.belts;
    if (actionName === 'COVER_TOGGLE') this.state.cover = !this.state.cover;
    if (actionName === 'AI_WORKER') this.state.aiActive = !this.state.aiActive;
  }
}

module.exports = DemoSimulator;
