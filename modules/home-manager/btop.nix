{ config, pkgs, lib, ... }: let
  c = config.lib.stylix.colors;
  toHex = hex: "#" + hex;
  bg = toHex c.base00;
  fg = toHex c.base05;
  accent = toHex c.base0D;
in {
  # ── btop: HM-managed, stylix-themed ──────────────────────────
  # 2026-07-15: previously an orphaned plain ~/.config/btop/btop.conf
  # pointed color_theme="noctalia" at a frozen v4 snapshot, bypassing
  # stylix. HM already wrote btop/themes/stylix.theme from base16; we now
  # enable programs.btop and point at it, carrying over every custom
  # setting from the old orphan so nothing is silently dropped.
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "stylix";

      # ── Layout / presets (from old orphan) ───────────────────
      disable_presets = "Off";
      presets = "cpu:1:default,proc:0:default cpu:0:default,mem:0:default,net:0:default cpu:0:block,net:0:tty";
      shown_boxes = "cpu mem net proc";

      # ── Graphs ───────────────────────────────────────────────
      graph_symbol = "braille";
      graph_symbol_cpu = "default";
      graph_symbol_gpu = "default";
      graph_symbol_mem = "default";
      graph_symbol_net = "default";
      graph_symbol_proc = "default";

      # ── Process list ─────────────────────────────────────────
      proc_sorting = "cpu lazy";
      proc_reversed = false;
      proc_tree = false;
      proc_colors = true;
      proc_gradient = true;
      proc_per_core = false;
      proc_mem_bytes = true;
      proc_cpu_graphs = true;
      proc_info_smaps = false;
      proc_left = false;
      proc_filter_kernel = false;
      proc_follow_detailed = true;
      proc_aggregate = false;

      # ── CPU box ──────────────────────────────────────────────
      update_ms = 1000;
      cpu_graph_upper = "Auto";
      cpu_graph_lower = "Auto";
      show_gpu_info = "Auto";
      cpu_invert_lower = true;
      cpu_single_graph = false;
      cpu_bottom = false;
      show_uptime = true;
      show_cpu_watts = true;
      check_temp = true;
      cpu_sensor = "Auto";
      show_coretemp = true;
      cpu_core_map = "";

      # ── Units / display ──────────────────────────────────────
      temp_scale = "celsius";
      base_10_sizes = false;
      show_cpu_freq = true;
      freq_mode = "first";
      clock_format = "%X";
      background_update = true;
      custom_cpu_name = "";

      # ── Disks ────────────────────────────────────────────────
      disks_filter = "";
      mem_graphs = true;
      mem_below_net = false;
      zfs_arc_cached = true;
      show_swap = true;
      swap_disk = true;
      show_disks = true;
      only_physical = true;
      use_fstab = true;
      zfs_hide_datasets = false;
      disk_free_priv = false;
      show_io_stat = true;
      io_mode = false;
      io_graph_combined = false;
      io_graph_speeds = "";

      # ── Network ──────────────────────────────────────────────
      swap_upload_download = false;
      net_download = 100;
      net_upload = 100;
      net_auto = true;
      net_sync = true;
      net_iface = "";
      base_10_bitrate = "Auto";

      # ── Battery ──────────────────────────────────────────────
      show_battery = true;
      selected_battery = "Auto";
      show_battery_watts = true;

      # ── Logging ──────────────────────────────────────────────
      log_level = "WARNING";
      save_config_on_exit = true;

      # ── GPU ───────────────────────────────────────────────────
      nvml_measure_pcie_speeds = true;
      rsmi_measure_pcie_speeds = true;
      gpu_mirror_graph = true;
      shown_gpus = "nvidia amd intel";
      custom_gpu_name0 = "";
      custom_gpu_name1 = "";
      custom_gpu_name2 = "";
      custom_gpu_name3 = "";
      custom_gpu_name4 = "";
      custom_gpu_name5 = "";

      # ── Mouse / rendering ────────────────────────────────────
      disable_mouse = false;
      rounded_corners = true;
      terminal_sync = true;
      keep_dead_proc_usage = false;
    };
  };

  # ── Stylix-generated btop theme (base16 → btop theme format) ──
  xdg.configFile."btop/themes/stylix.theme".text = ''
    theme[main_bg]="${bg}"
    theme[main_fg]="${fg}"
    theme[title]="${fg}"
    theme[hi_fg]="${accent}"
    theme[selected_bg]="${toHex c.base03}"
    theme[selected_fg]="${accent}"
    theme[inactive_fg]="${toHex c.base03}"
    theme[graph_text]="${fg}"
    theme[meter_bg]="${toHex c.base03}"
    theme[proc_misc]="${fg}"
    theme[cpu_box]="${toHex c.base0E}"
    theme[mem_box]="${toHex c.base0B}"
    theme[net_box]="${toHex c.base08}"
    theme[proc_box]="${accent}"
    theme[div_line]="${toHex c.base03}"
    theme[temp_start]="${toHex c.base0B}"
    theme[temp_mid]="${toHex c.base0A}"
    theme[temp_end]="${toHex c.base08}"
    theme[cpu_start]="${toHex c.base0C}"
    theme[cpu_mid]="${accent}"
    theme[cpu_end]="${toHex c.base0E}"
    theme[free_start]="${toHex c.base0E}"
    theme[free_mid]="${accent}"
    theme[free_end]="${toHex c.base0C}"
    theme[cached_start]="${accent}"
    theme[cached_mid]="${toHex c.base0C}"
    theme[cached_end]="${toHex c.base0E}"
    theme[available_start]="${toHex c.base0A}"
    theme[available_mid]="${toHex c.base08}"
    theme[available_end]="${toHex c.base08}"
    theme[used_start]="${toHex c.base0B}"
    theme[used_mid]="${toHex c.base0C}"
    theme[used_end]="${accent}"
    theme[download_start]="${toHex c.base0A}"
    theme[download_mid]="${toHex c.base08}"
    theme[download_end]="${toHex c.base08}"
    theme[upload_start]="${toHex c.base0B}"
    theme[upload_mid]="${toHex c.base0C}"
    theme[upload_end]="${accent}"
    theme[process_start]="${toHex c.base0C}"
    theme[process_mid]="${accent}"
    theme[process_end]="${toHex c.base0E}"
  '';
}
