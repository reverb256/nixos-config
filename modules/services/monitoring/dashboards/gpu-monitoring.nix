# GPU Monitoring Dashboard
# Detailed GPU metrics including temperature, power, memory, and utilization
{lib, ...}: let
  inherit (lib.dashboard) panels template grid thresholds;
in {
  gpuMonitoring = template {
    title = "🎮 GPU Monitoring";
    description = "Comprehensive GPU health and performance metrics";
    tags = ["gpu" "nvidia" "hardware"];
    panels = [
      # ========== ROW: GPU OVERVIEW ==========
      (panels.row "🖥️ GPU Overview" false)
      # Active GPUs
      (panels.stat {
        title = "Active GPUs";
        expr = "count(nvidia_smi_gpu_clocks_current_graphics_hz)";
        gridPos = {h = 4; w = 6; x = 0; y = 1;};
        colorMode = "value";
      })
      # Total Power Draw
      (panels.stat {
        title = "Total Power Draw";
        expr = "sum(nvidia_smi_power_draw_watts)";
        gridPos = {h = 4; w = 6; x = 6; y = 1;};
        unit = "watt";
        colorMode = "value";
      })
      # Avg Temperature
      (panels.gauge {
        title = "Avg GPU Temperature";
        expr = "avg(nvidia_smi_temperature_gpu)";
        gridPos = {h = 4; w = 6; x = 12; y = 1;};
        thresholds = thresholds.temperature;
        unit = "celsius";
      })
      # Total VRAM Used
      (panels.stat {
        title = "Total VRAM Used";
        expr = "sum(nvidia_smi_memory_used_bytes) / 1024 / 1024 / 1024";
        gridPos = {h = 4; w = 6; x = 18; y = 1;};
        unit = "decibytes";
        colorMode = "value";
      })

      # ========== ROW: UTILIZATION ==========
      (panels.row "📊 GPU Utilization" false)
      # GPU Utilization Timeseries
      (panels.timeseries {
        title = "GPU Utilization";
        expr = "nvidia_smi_utilization_gpu_ratio * 100";
        gridPos = {h = 8; w = 12; x = 0; y = 5;};
        unit = "percent";
        legendFormat = "{{instance}}";
      })
      # Memory Utilization
      (panels.timeseries {
        title = "Memory Utilization";
        expr = "nvidia_smi_utilization_memory_ratio * 100";
        gridPos = {h = 8; w = 12; x = 12; y = 5;};
        unit = "percent";
        legendFormat = "{{instance}}";
      })

      # ========== ROW: TEMPERATURES ==========
      (panels.row "🌡️ Temperature & Power" true)
      # Temperature per GPU
      (panels.timeseries {
        title = "GPU Temperature";
        expr = "nvidia_smi_temperature_gpu";
        gridPos = {h = 8; w = 12; x = 0; y = 13;};
        unit = "celsius";
        legendFormat = "{{instance}}";
      })
      # Power Draw per GPU
      (panels.timeseries {
        title = "Power Draw";
        expr = "nvidia_smi_power_draw_watts";
        gridPos = {h = 8; w = 12; x = 12; y = 13;};
        unit = "watt";
        legendFormat = "{{instance}}";
      })

      # ========== ROW: CLOCK SPEEDS ==========
      (panels.row "⚡ Clock Speeds" true)
      # Graphics Clock
      (panels.timeseries {
        title = "Graphics Clock";
        expr = "nvidia_smi_clocks_current_graphics_hz";
        gridPos = {h = 8; w = 8; x = 0; y = 21;};
        unit = "hertz";
        legendFormat = "{{instance}}";
      })
      # Memory Clock
      (panels.timeseries {
        title = "Memory Clock";
        expr = "nvidia_smi_clocks_current_memory_clock_hz";
        gridPos = {h = 8; w = 8; x = 8; y = 21;};
        unit = "hertz";
        legendFormat = "{{instance}}";
      })
      # SM Clock
      (panels.timeseries {
        title = "SM Clock";
        expr = "nvidia_smi_clocks_current_sm_clock_hz";
        gridPos = {h = 8; w = 8; x = 16; y = 21;};
        unit = "hertz";
        legendFormat = "{{instance}}";
      })

      # ========== ROW: VRAM USAGE ==========
      (panels.row "💾 VRAM Usage" true)
      # VRAM Usage per GPU
      (panels.timeseries {
        title = "VRAM Usage";
        expr = "nvidia_smi_memory_used_bytes / nvidia_smi_memory_total_bytes * 100";
        gridPos = {h = 8; w = 12; x = 0; y = 29;};
        unit = "percent";
        legendFormat = "{{instance}}";
      })
      # VRAM Absolute Values
      (panels.timeseries {
        title = "VRAM Used (GB)";
        expr = "nvidia_smi_memory_used_bytes / 1024 / 1024 / 1024";
        gridPos = {h = 8; w = 12; x = 12; y = 29;};
        unit = "decibytes";
        legendFormat = "{{instance}}";
      })

      # ========== ROW: PERFORMANCE STATES ==========
      (panels.row "📈 Performance States" true)
      # Throttling Indicators
      {
        datasource = lib.dashboard.prometheusDatasource;
        fieldConfig.defaults = {
          color.mode = "thresholds";
          mappings = [
            {type = "value"; options = {"0" = {color = "green"; text = "None";}; "1" = {color = "yellow"; text = "Active";};};}
          ];
          thresholds.mode = "absolute";
        };
        gridPos = {h = 6; w = 24; x = 0; y = 37;};
        options = {
          graphMode = "none";
          reduceOptions = {calcs = ["lastNotNull"]; fields = ""; values = false;};
        };
        targets = [
          {expr = "nvidia_smi_clocks_event_reasons_hw_power_brake_slowdown"; legendFormat = "Power Brake {{instance}}"; refId = "A";}
          {expr = "nvidia_smi_clocks_event_reasons_hw_thermal_slowdown"; legendFormat = "Thermal {{instance}}"; refId = "B";}
          {expr = "nvidia_smi_clocks_event_reasons_hw_slowdown"; legendFormat = "HW Slowdown {{instance}}"; refId = "C";}
        ];
        title = "Throttling Indicators";
        type = "stat";
      }

      # ========== ROW: FAN & COOLING ==========
      (panels.row "❄️ Cooling" true)
      # Fan Speed
      (panels.timeseries {
        title = "Fan Speed";
        expr = "nvidia_smi_fan_speed_ratio * 100";
        gridPos = {h = 8; w = 12; x = 0; y = 43;};
        unit = "percent";
        legendFormat = "{{instance}}";
      })
      # Power Limit
      (panels.timeseries {
        title = "Power Limit vs Current Draw";
        expr = "nvidia_smi_power_draw_watts";
        gridPos = {h = 8; w = 12; x = 12; y = 43;};
        unit = "watt";
        legendFormat = "{{instance}}";
      })
    ];
  };
}
