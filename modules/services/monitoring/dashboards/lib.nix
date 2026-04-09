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
        lineStyle = {fill = "solid";};
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
      {
        color = "red";
        value = null;
      }
      {
        color = "green";
        value = 1;
      }
    ];

    # Percentage (0-100%)
    percentage = [
      {
        color = "green";
        value = null;
      }
      {
        color = "yellow";
        value = 70;
      }
      {
        color = "orange";
        value = 85;
      }
      {
        color = "red";
        value = 95;
      }
    ];

    # Error rate
    errorRate = [
      {
        color = "green";
        value = null;
      }
      {
        color = "yellow";
        value = 0.01;
      }
      {
        color = "orange";
        value = 0.05;
      }
      {
        color = "red";
        value = 0.1;
      }
    ];

    # Latency (seconds)
    latency = [
      {
        color = "green";
        value = null;
      }
      {
        color = "yellow";
        value = 0.5;
      }
      {
        color = "orange";
        value = 1.0;
      }
      {
        color = "red";
        value = 2.0;
      }
    ];

    # Temperature (Celsius)
    temperature = [
      {
        color = "green";
        value = null;
      }
      {
        color = "yellow";
        value = 60;
      }
      {
        color = "orange";
        value = 75;
      }
      {
        color = "red";
        value = 85;
      }
    ];

    # Load average multiplier
    loadMultiplier = [
      {
        color = "green";
        value = null;
      }
      {
        color = "yellow";
        value = 1;
      }
      {
        color = "orange";
        value = 2;
      }
      {
        color = "red";
        value = 4;
      }
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
    fullWidth = {
      h = 1;
      w = 24;
      x = 0;
      y = 0;
    };
    quarter = {
      h = 8;
      w = 6;
      x = 0;
      y = 1;
    };
    half = {
      h = 8;
      w = 12;
      x = 0;
      y = 1;
    };
    threeQuarter = {
      h = 8;
      w = 18;
      x = 0;
      y = 1;
    };
    smallStat = {
      h = 4;
      w = 4;
      x = 0;
      y = 0;
    };
    mediumStat = {
      h = 6;
      w = 6;
      x = 0;
      y = 0;
    };
    largeStat = {
      h = 8;
      w = 8;
      x = 0;
      y = 0;
    };
  };

  # Panel builders
  panels = {
    # Create a row header
    row = title: collapsed: {
      inherit collapsed;
      gridPos = {
        h = 1;
        w = 24;
        x = 0;
        y = 0;
      };
      panels = [];
      inherit title;
      type = "row";
    };

    # Create a stat panel
    statPanel = {
      title,
      expr,
      legendFormat ? "",
      gridPos,
      thresholds ? [],
      colorMode ? "value",
      unit ? "none",
    }: {
      datasource = prometheusDatasource;
      fieldConfig.defaults =
        fieldConfigs.thresholdColor thresholds
        // {
          inherit unit;
        };
      inherit gridPos;
      options = {
        graphMode =
          if colorMode == "background"
          then "none"
          else "area";
        inherit colorMode;
        reduceOptions = {
          calcs = ["lastNotNull"];
          fields = "";
          values = false;
        };
      };
      targets = [
        {
          inherit expr;
          inherit legendFormat;
          refId = "A";
        }
      ];
      inherit title;
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
        custom =
          if custom != null
          then custom
          else fieldConfigs.paletteClassic.custom;
        inherit unit;
      };
      fieldConfig =
        if thresholds != null
        then
          baseFieldConfig
          // {
            color.mode = "thresholds";
            thresholds.mode = "absolute";
            thresholds.steps = thresholds;
          }
        else baseFieldConfig;
    in {
      datasource = prometheusDatasource;
      fieldConfig.defaults = fieldConfig;
      inherit gridPos;
      options = {
        legend = {
          calcs = ["mean" "max" "last"];
          displayMode = "table";
          placement = "bottom";
        };
        tooltip.mode = "multi";
      };
      targets =
        if builtins.isList expr
        then
          (lib.imap0 (_i: e: {
              expr = e;
              inherit legendFormat;
              refId = lib.toUpper "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
            })
            expr)
        else [
          {
            inherit expr;
            inherit legendFormat;
            refId = "A";
          }
        ];
      inherit title;
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
        inherit unit;
        inherit min;
        inherit max;
      };
      inherit gridPos;
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
      targets = [
        {
          inherit expr;
          legendFormat = "";
          refId = "A";
        }
      ];
      inherit title;
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
          hideFrom = {
            tooltip = false;
            vizLegend = false;
            yaxis = false;
          };
        };
        inherit unit;
      };
      inherit gridPos;
      options = {
        legend = {
          displayMode = "table";
          placement = "right";
          values = ["value" "percent"];
        };
        inherit pieType;
      };
      targets = [
        {
          inherit expr;
          legendFormat = "{{{{ {0} }}}}";
          refId = "A";
        }
      ];
      inherit title;
      type = "piechart";
    };

    # Create a table panel
    table = {
      title,
      expr,
      gridPos,
    }: {
      datasource = prometheusDatasource;
      inherit gridPos;
      options = {
        showHeader = true;
      };
      targets = [
        {
          inherit expr;
          format = "table";
          refId = "A";
        }
      ];
      inherit title;
      transformations = [
        {
          id = "organize";
          options = {
            excludeByName = {};
            indexByName = {};
            renameByName = {};
          };
        }
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
    inherit description;
    editable = true;
    fiscalYearStartMonth = 0;
    graphTooltip = 1;
    id = null;
    links = [];
    liveNow = false;
    inherit panels;
    inherit tags;
    inherit title;
    # Generate valid UID: remove emoji, replace spaces/slashes with dashes, lowercase
    # Grafana UIDs can only contain: a-z, 0-9, -, _
    # Uses lib.pipe for clean functional transformation pipeline
    uid = lib.pipe title [
      # Remove emoji sequentially (each stage receives output of previous)
      (builtins.replaceStrings ["🏠"] [""])
      (builtins.replaceStrings ["🔍"] [""])
      (builtins.replaceStrings ["⛏️"] [""])
      (builtins.replaceStrings ["🎮"] [""])
      (builtins.replaceStrings ["🤖"] [""])
      (builtins.replaceStrings ["📊"] [""])
      (builtins.replaceStrings ["💾"] [""])
      (builtins.replaceStrings ["🚀"] [""])
      (builtins.replaceStrings ["⚡"] [""])
      (builtins.replaceStrings ["🌡️"] [""])
      (builtins.replaceStrings ["🔬"] [""])
      # Replace spaces and slashes with dashes
      (builtins.replaceStrings [" " "/"] ["-" "-"])
      # Normalize: trim whitespace, strip leading/trailing dashes, lowercase
      lib.strings.trim
      (s: lib.strings.removePrefix "-" (lib.strings.removeSuffix "-" s))
      lib.toLower
    ];
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
