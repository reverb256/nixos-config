{ config, pkgs, lib, hostName, ... }:
let
  c = config.lib.stylix.colors.withHashtag;
  isSentry = hostName == "sentry";

  minerScript = pkgs.writeShellScriptBin "miner-status" ''
    set -euo pipefail
    for port in 21550 21551; do
      if data=$(curl -sf --max-time 2 "http://localhost:$port/" 2>/dev/null); then
        hash=$(echo "$data" | python3 -c "
    import sys, json
    try:
        d = json.loads(sys.stdin.read())
        hr = d.get('hashrate_total', d.get('hashrate', 0))
        if hr >= 1000000: print(f'{hr/1000000:.1f} GH/s')
        elif hr >= 1000: print(f'{hr/1000:.1f} MH/s')
        else: print(f'{hr:.0f} KH/s')
    except: print('?')" 2>/dev/null)
        if [ -n "$hash" ]; then echo "⛏ $hash"; exit 0; fi
      fi
    done
    if data=$(curl -sf --max-time 2 "http://localhost:3333/api/v1/status" 2>/dev/null); then
      hash=$(echo "$data" | python3 -c "
    import sys, json
    try:
        d = json.loads(sys.stdin.read())
        hr = d.get('hashrate', 0) or 0
        if hr >= 1000000: print(f'{hr/1000000:.1f} GH/s')
        elif hr >= 1000: print(f'{hr/1000:.1f} MH/s')
        else: print(f'{hr:.0f} KH/s')
    except: print('?')" 2>/dev/null)
      if [ -n "$hash" ]; then echo "⛏ $hash"; exit 0; fi
    fi
    exit 1
  '';
in {
  home.packages = lib.mkIf (!isSentry) [minerScript];
  programs.starship = {
    enable = true;
    settings = {
      format = if isSentry then ''
        $time$hostname
        $directory$git_branch$git_status$nix_shell$fill$cmd_duration
        $character'' else ''
        $time$hostname
        $directory$git_branch$git_status$nix_shell$custom.miner$fill$cmd_duration
        $character'';
      add_newline = false;
      time = { disabled = false; format = ''\[$time\]($style)''; style = "italic ${c.base03}"; use_12hr = false; time_format = "%R"; };
      hostname = { ssh_only = false; format = "[$hostname](bold ${c.base0B}) "; disabled = false; };
      directory = { truncation_length = 3; truncation_symbol = "…/"; style = "bold ${c.base0D}"; fish_style_pwd_dir_length = 0; };
      git_branch = { format = "on [$branch](italic ${c.base0D}) "; symbol = " "; };
      git_status = { format = "[($all_status$ahead_behind)](bold ${c.base0D}) "; ahead = "⇡"; behind = "⇣"; diverged = "⇕"; conflicted = "✖"; untracked = "•"; modified = "▲"; staged = "●"; stashed = "≡"; };
      nix_shell = { format = "[❄ $state($name)](bold ${c.base0A}) "; disabled = false; heuristic = true; };
      cmd_duration = { format = "[⏱ $duration](italic ${c.base03})"; show_milliseconds = false; min_time = 2000; };
      custom.miner = lib.mkIf (!isSentry) { command = "miner-status"; description = "GPU mining hashrate"; format = "[$output](bold ${c.base0C}) "; when = true; };
      character = { success_symbol = "[╰─❯](bold ${c.base0D})"; error_symbol = "[╰─✗](bold ${c.base08})"; vicmd_symbol = "[╰─❮](bold ${c.base0B})"; };
      fill.symbol = "─"; fill.style = "${c.base02}"; command_timeout = 10000;
      sudo.disabled = true; username.disabled = true; python.disabled = true; ruby.disabled = true;
      golang.disabled = true; rust.disabled = true; terraform.disabled = true; vagrant.disabled = true;
      conda.disabled = true; meson.disabled = true; spack.disabled = true; kubernetes.disabled = true;
      docker_context.disabled = true; nodejs.disabled = true; package.disabled = true; dart.disabled = true;
      elixir.disabled = true; haxe.disabled = true; julia.disabled = true; lua.disabled = true;
      perl.disabled = true; php.disabled = true; scala.disabled = true; swift.disabled = true; zig.disabled = true;
    };
  };
}
