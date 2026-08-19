# Storage + reboot + OOM diagnostic CLIs, installed on every host.
#
# WHY THIS IS A MODULE AND NOT A SCRIPT I SCP AROUND
# These began life as ad-hoc scripts copied to /tmp during the 2026-08-18 btrfs
# ENOSPC incident. That was wrong twice over: /tmp is cleared on reboot, so the
# tools vanish exactly when the next incident needs them, and hand-placed files
# are imperative state this repo forbids. Declaring them here means every host
# has them, at a known name, reproducibly, with their dependencies pinned into
# the closure instead of relying on whatever happens to be on PATH.
#
# WHAT THEY EXIST TO PREVENT
# `df` is actively misleading on btrfs. A filesystem can report tens of GiB free
# and still fail every write, because free space inside Data chunks cannot serve
# Metadata. The real signal is `Device unallocated` reaching zero WHILE Metadata
# approaches its total. On 2026-08-18 that combination took sentry down hard
# (0 bytes, 1017 ENOSPC events, the Nix SQLite DB unwritable) and left nexus one
# step behind it (Metadata 95%, unallocated 1.00MiB, every CI runner dead).
#
# Each tool encodes a lesson learned the hard way during that incident:
#   btrfs-check   — reports EVERY btrfs filesystem, because hosts here do not all
#                   put /nix on the root device (zephyr's /nix is nvme1n1p2), and
#                   auditing only `/` measures the wrong disk.
#   boot-check    — identifies a reboot by BOOT ID, not uptime, and says whether
#                   the previous boot ended gracefully or was a hard crash.
#   oom-check     — counts real kill EVENTS, excluding earlyoom's startup banner
#                   (matching that banner once produced a false "16 OOM kills").
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.storage-diagnostics;

  # Dependencies are resolved from the closure, not the ambient PATH, so these
  # keep working in a rescue shell or a degraded environment.
  diagPath = lib.makeBinPath [
    pkgs.btrfs-progs
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gawk
    pkgs.systemd
    pkgs.util-linux
  ];

  # ---------------------------------------------------------------------------
  # btrfs-check — the three numbers that actually diagnose btrfs, per filesystem
  # ---------------------------------------------------------------------------
  btrfsCheck = pkgs.writeShellApplication {
    name = "btrfs-check";
    runtimeInputs = [pkgs.btrfs-progs pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.util-linux];
    text = ''
      # Enumerate btrfs mounts from /proc/mounts and dedupe by DEVICE, so a host
      # with several btrfs filesystems reports all of them exactly once.
      printf '%-14s %-20s %-11s %-20s %-6s %s\n' MOUNT DEVICE UNALLOC METADATA DF RECLAIM
      seen=""
      while read -r dev mnt fstype _rest; do
        [ "$fstype" = "btrfs" ] || continue
        case " $seen " in *" $dev "*) continue ;; esac
        seen="$seen $dev"

        unalloc=$(btrfs filesystem usage "$mnt" 2>/dev/null \
                  | awk '/Device unallocated/{print $3}')

        meta=$(btrfs filesystem df "$mnt" 2>/dev/null \
               | awk '/^Metadata/{
                        for (i=1;i<=NF;i++) {
                          if ($i ~ /^total=/) { t=$i; sub(/^total=/,"",t); sub(/,$/,"",t) }
                          if ($i ~ /^used=/)  { u=$i; sub(/^used=/,"",u) }
                        }
                        printf "%s/%s", u, t
                      }')

        dfpct=$(df -h "$mnt" 2>/dev/null | awk 'NR==2{print $5}')

        # Reclaim state is per-filesystem under /sys/fs/btrfs/<uuid>/.
        uuid=$(btrfs filesystem show "$mnt" 2>/dev/null | awk '/uuid:/{print $NF; exit}')
        rc="n/a"
        knob="/sys/fs/btrfs/$uuid/allocation/data"
        if [ -n "$uuid" ] && [ -r "$knob/dynamic_reclaim" ]; then
          rc="dyn=$(cat "$knob/dynamic_reclaim" 2>/dev/null) count=$(cat "$knob/reclaim_count" 2>/dev/null)"
        fi

        printf '%-14s %-20s %-11s %-20s %-6s %s\n' \
          "$mnt" "$dev" "''${unalloc:-?}" "''${meta:-?}" "''${dfpct:-?}" "$rc"
      done < /proc/mounts

      echo
      # ENOSPC events are the ground truth for whether a host is actually
      # failing, as opposed to merely looking full.
      n=$(journalctl --since '24 hours ago' --no-pager 2>/dev/null \
          | grep -ciE 'no space left|ENOSPC' || true)
      echo "ENOSPC events (24h): ''${n:-0}"
      echo
      echo "DANGER = unallocated at/near 0 AND Metadata used near Metadata total."
      echo "Zero unallocated alone is survivable when Metadata still has headroom."
    '';
  };

  # ---------------------------------------------------------------------------
  # boot-check — reboot detection by boot ID, plus crash-vs-graceful
  # ---------------------------------------------------------------------------
  bootCheck = pkgs.writeShellApplication {
    name = "boot-check";
    runtimeInputs = [pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.systemd];
    text = ''
      # Boot ID is the definitive identity of the current boot. Uptime only ever
      # counts up, so it cannot by itself tell you a reboot just happened.
      echo "boot id : $(cat /proc/sys/kernel/random/boot_id)"
      awk '{printf "uptime  : %.2f hours (%d sec)\n", $1/3600, $1}' /proc/uptime
      echo "now     : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
      echo

      echo "boot history:"
      journalctl --list-boots --no-pager 2>/dev/null | tail -5
      echo

      # A graceful shutdown leaves a shutdown sequence in the journal. A hard
      # crash simply stops mid-log. That distinction is the whole point.
      if journalctl -b -1 --no-pager >/dev/null 2>&1; then
        if journalctl -b -1 --no-pager 2>/dev/null | tail -30 \
             | grep -qiE 'Reached target (Shutdown|Reboot)|systemd-shutdown|Stopping .*systemd'; then
          echo "previous boot: ended GRACEFULLY (shutdown sequence present)"
        else
          echo "previous boot: ended ABRUPTLY — no shutdown sequence => HARD CRASH"
          echo "last 5 lines before it stopped:"
          journalctl -b -1 --no-pager 2>/dev/null | tail -5
        fi
      else
        echo "previous boot: no journal retained"
      fi
    '';
  };

  # ---------------------------------------------------------------------------
  # oom-check — real kill events only
  # ---------------------------------------------------------------------------
  oomCheck = pkgs.writeShellApplication {
    name = "oom-check";
    runtimeInputs = [pkgs.coreutils pkgs.gnugrep pkgs.systemd pkgs.procps];
    text = ''
      # Match kill EVENTS only. A naive grep for 'Out of memory|earlyoom' also
      # matches earlyoom's startup banner ("sending SIGTERM when mem avail <=
      # 12.00% ...") which is a threshold declaration, not an action — that
      # false positive once produced a bogus "16 OOM kills" report.
      KILL_RE='oom-kill:|Out of memory: Killed|Killed process [0-9]+|sending SIGKILL to process [0-9]+|systemd-oomd.*Killed'

      for b in 0 -1; do
        echo "--- boot $b ---"
        if journalctl -b "$b" --no-pager >/dev/null 2>&1; then
          n=$(journalctl -b "$b" --no-pager 2>/dev/null | grep -cEi "$KILL_RE" || true)
          echo "real kill events: ''${n:-0}"
          if [ "''${n:-0}" -gt 0 ]; then
            journalctl -b "$b" --no-pager 2>/dev/null | grep -Ei "$KILL_RE" | tail -8
          fi
        else
          echo "no journal for this boot"
        fi
        echo
      done

      echo "--- memory now ---"
      free -h
      echo
      # PSI is the strongest signal: 0.00 across all windows means the kernel
      # reports no memory stall at all.
      echo "PSI memory (0.00 across windows = no stall):"
      cat /proc/pressure/memory 2>/dev/null || echo "(PSI unavailable)"
      echo
      echo "killers: earlyoom=$(systemctl is-active earlyoom 2>/dev/null) systemd-oomd=$(systemctl is-active systemd-oomd 2>/dev/null)"
    '';
  };
in {
  options.services.storage-diagnostics = {
    enable =
      lib.mkEnableOption ''
        the btrfs-check / boot-check / oom-check diagnostic CLIs on this host.

        Read-only tools. They inspect state and print it; none of them modify
        the filesystem, so they are safe to run during an incident
      ''
      // {
        default = true;
      };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [btrfsCheck bootCheck oomCheck];

    # Keep the resolved PATH available to anything else that wants the same
    # tool set (rescue shells, activation scripts).
    environment.sessionVariables.STORAGE_DIAG_PATH = diagPath;
  };
}
