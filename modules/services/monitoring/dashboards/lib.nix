# Dashboard Library - Reusable Panel Builders
# Provides composable functions for building Grafana dashboards
{lib, ...}: let
  # Common datasource reference
  prometheusDatasource = {
    type = "prometheus";
    uid = "prometheus";
  };

  # Standard field configs
  fieldConfigs = {
    # Color mode with thresholds
    thresholdColor = steps: {
      color.mode = "thresholds";
      thresholds.mode = "absolute";
      thresholds.steps = steps;
    };

    # Classic palette for timeseries
    paletteClassic = {
      color.mode = "palette-classic";
      custom = {
        axisCenteredZero = false;
        axisColorMode = "text";
        drawStyle = "line";
        fillOpacity = 10;
        gradientMode = "scheme";
        lineInterpolation = "smooth";
        lineWidth = 2;
        spanNulls = true;
      };
    };

    # Area chart style
    areaStyle = {
      color.mode = "palette-classic";
      custom = {
        axisCenteredZero = false;
        axisColorMode = "text";
        drawStyle = "line";
        fillOpacity = 20;
        gradientMode = "scheme";
        lineInterpolation = "smooth";
        lineWidth = 2;
        spanNulls = true;
        lineStyle = { fill = "solid"; };
      };
    };

    # Bar chart style
    barStyle = {
      color.mode = "palette-classic";
      custom = {
        axisCenteredZero = false;
        axisColorMode = "text";
        drawStyle = "bars";
        fillOpacity = 80;
        gradientMode = "none";
        lineInterpolation = "linear";
        lineWidth = 1;
        spanNulls = true;
      };
    };
  };

  # Common thresholds
  thresholds = {
    # 0-1 binary (up/down)
    binary = [
      {color = "red"; value = null;}
      {color = "green"; value = 1;}
    ];

    # Percentage (0-100%)
    percentage = [
      {color = "green"; value = null;}
      {color = "yellow"; value = 70;}
      {color = "orange"; value = 85;}
      {color = "red"; value = 95;}
    ];

    # Error rate
    errorRate = [
      {color = "green"; value = null;}
      {color = "yellow"; value = 0.01;}
      {color = "orange"; value = 0.05;}
      {color = "red"; value = 0.1;}
    ];

    # Latency (seconds)
    latency = [
      {color = "green"; value = null;}
      {color = "yellow"; value = 0.5;}
      {color = "orange"; value = 1.0;}
      {color = "red"; value = 2.0;}
    ];

    # Temperature (Celsius)
    temperature = [
      {color = "green"; value = null;}
      {color = "yellow"; value = 60;}
      {color = "orange"; value = 75;}
      {color = "red"; value = 85;}
    ];

    # Load average multiplier
    loadMultiplier = [
      {color = "green"; value = null;}
      {color = "yellow"; value = 1;}
      {color = "orange"; value = 2;}
      {color = "red"; value = 4;}
    ];
  };

  # Common units
  units = {
    percent = "percent";
    percentunit = "percentunit";
    bytes = "bytes";
    bytesPerSec = "Bps";
    seconds = "s";
    short = "short";
    none = "none";
  };

  # Standard grid positions (24-column grid)
  grid = {
    fullWidth = {h = 1; w = 24; x = 0; y = 0;};
    quarter = {h = 8; w = 6; x = 0; y = 1;};
    half = {h = 8; w = 12; x = 0; y = 1;};
    threeQuarter = {h = 8; w = 18; x = 0; y = 1;};
    smallStat = {h = 4; w = 4; x = 0; y = 0;};
    mediumStat = {h = 6; w = 6; x = 0; y = 0;};
    largeStat = {h = 8; w = 8; x = 0; y = 0;};
  };

  # Panel builders
  panels = {
    # Create a row header
    row = title: collapsed: {
      collapsed = collapsed;
      gridPos = {h = 1; w = 24; x = 0; y = 0;};
      panels = [];
      title = title;
      type = "row";
    };

    # Create a stat panel
    stat = {
      title,
      expr,
      legendFormat ? "",
      gridPos,
      thresholds ? [],
      unit ? "none",
      colorMode ? "value",
    }: {
      datasource = prometheusDatasource;
      fieldConfig.defaults = fieldConfigs.thresholdColor thresholds;
      gridPos = gridPos;
      options = {
        graphMode = if colorMode == "background" then "none" else "area";
        colorMode = colorMode;
        reduceOptions = {
          calcs = ["lastNotNull"];
          fields = "";
          values = false;
        };
      };
      targets = [{expr = expr; legendFormat = legendFormat; refId = "A";}];
      title = title;
      type = "stat";
    };

    # Create a timeseries panel
    timeseries = {
      title,
      expr,
      gridPos,
      legendFormat ? "",
      unit ? "none",
      custom ? null,
      thresholds ? null,
    }: let
      # Build field config defaults
      baseFieldConfig = {
        color.mode = "palette-classic";
        custom = if custom != null then custom else fieldConfigs.paletteClassic.custom;
        unit = unit;
      };
      fieldConfig = if thresholds != null
        then baseFieldConfig // {
          color.mode = "thresholds";
          thresholds.mode = "absolute";
          thresholds.steps = thresholds;
        }
        else baseFieldConfig;
    in {
      datasource = prometheusDatasource;
      fieldConfig.defaults = fieldConfig;
      gridPos = gridPos;
      options = {
        legend = {calcs = ["mean" "max" "last"]; displayMode = "table"; placement = "bottom";};
        tooltip.mode = "multi";
      };
      targets = if builtins.isList expr
        then (lib.imap0 (i: e: {expr = e; legendFormat = legendFormat; refId = lib.toUpper "ABCDEFGHIJKLMNOPQRSTUVWXYZ";}) expr)
        else [{expr = expr; legendFormat = legendFormat; refId = "A";}];
      title = title;
      type = "timeseries";
    };

    # Create a gauge panel
    gauge = {
      title,
      expr,
      gridPos,
      min ? 0,
      max ? 100,
      thresholds,
      unit ? "none",
    }: {
      datasource = prometheusDatasource;
      fieldConfig.defaults = {
        color.mode = "thresholds";
        thresholds.mode = "absolute";
        thresholds.steps = thresholds;
        unit = unit;
        min = min;
        max = max;
      };
      gridPos = gridPos;
      options = {
        orientation = "auto";
        reduceOptions = {
          calcs = ["lastNotNull"];
          fields = "";
          values = false;
        };
        showThresholdLabels = false;
        showThresholdMarkers = true;
      };
      targets = [{expr = expr; legendFormat = ""; refId = "A";}];
      title = title;
      type = "gauge";
    };

    # Create a piechart/donut panel
    piechart = {
      title,
      expr,
      gridPos,
      unit ? "none",
      pieType ? "donut",
    }: {
      datasource = prometheusDatasource;
      fieldConfig.defaults = {
        color.mode = "palette-classic";
        custom = {
          hideFrom = {tooltip = false; vizLegend = false; yaxis = false;};
        };
        unit = unit;
      };
      gridPos = gridPos;
      options = {
        legend = {displayMode = "table"; placement = "right"; values = ["value" "percent"];};
        pieType = pieType;
      };
      targets = [{expr = expr; legendFormat = "{{{{ {0} }}}}" ; refId = "A";}];
      title = title;
      type = "piechart";
    };

    # Create a table panel
    table = {
      title,
      expr,
      gridPos,
      columns ? ["instance" "job"],
    }: {
      datasource = prometheusDatasource;
      gridPos = gridPos;
      options = {
        showHeader = true;
      };
      targets = [{expr = expr; format = "table"; refId = "A";}];
      title = title;
      transformations = [
        {id = "organize"; options = {excludeByName = {}; indexByName = {}; renameByName = {};};}
      ];
      type = "table";
    };
  };

  # Dashboard template
  template = {
    title,
    description ? "",
    tags ? [],
    panels ? [],
  }: {
    annotations.list = [];
    description = description;
    editable = true;
    fiscalYearStartMonth = 0;
    graphTooltip = 1;
    id = null;
    links = [];
    liveNow = false;
    panels = panels;
    tags = tags;
    title = title;
    # Generate valid UID: remove emoji, replace spaces/slashes with dashes, lowercase
    # Grafana UIDs can only contain: a-z, 0-9, -, _
    uid = let
      # Remove each emoji individually (replaceStrings requires equal length arrays)
      # Include all emoji used in dashboard titles
      s1 = builtins.replaceStrings ["🏠"] [""] title;
      s2 = builtins.replaceStrings ["🔍"] [""] s1;
      s3 = builtins.replaceStrings ["⛏️"] [""] s2;
      s4 = builtins.replaceStrings ["🎮"] [""] s3;
      s5 = builtins.replaceStrings ["🤖"] [""] s4;
      s6 = builtins.replaceStrings ["📊"] [""] s5;
      s7 = builtins.replaceStrings ["💾"] [""] s6;
      s8 = builtins.replaceStrings ["🚀"] [""] s7;
      s9 = builtins.replaceStrings ["⚡"] [""] s8;
      s10 = builtins.replaceStrings ["🌡️"] [""] s9;
      s11 = builtins.replaceStrings ["🔬"] [""] s10;
      # Replace spaces and slashes with dashes
      normalized = builtins.replaceStrings [" " "/"] ["-" "-"] s11;
      # Strip leading/trailing dashes and whitespace, then lowercase
      stripped = lib.strings.removePrefix "-" (lib.strings.removeSuffix "-" normalized);
    in
      lib.toLower (lib.strings.trim stripped);
    timezone = "";
    weekStart = "";
  };
in {
  inherit
    prometheusDatasource
    fieldConfigs
    thresholds
    units
    grid
    panels
    template
    ;
}
