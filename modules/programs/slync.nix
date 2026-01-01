{ pkgs, ... }:

{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "slync";
      runtimeInputs = [ pkgs.docopts pkgs.fswatch pkgs.rsync pkgs.git ];
      text = ''
        # slync - fswatch-based file synchronizer
        #
        # Usage:
        #   slync start <remote> [<remote_path>]
        #   slync stop [<remote>]
        #   slync list
        #   slync logs
        #   slync -h | --help
        #
        # Commands:
        #   start     Start syncing current directory to remote
        #   stop      Stop syncing (specific remote or all)
        #   list      List active sync sessions
        #   logs      Tail logs for current directory's sync
        #
        # Arguments:
        #   <remote>       Remote host (e.g., user@host)
        #   <remote_path>  Remote path (defaults to current directory path)

        STATE_DIR="''${HOME}/.local/state/slync"
        LOG_DIR="$STATE_DIR/logs"
        mkdir -p "$STATE_DIR" "$LOG_DIR"

        do_sync() {
          local remote="$1"
          local remote_path="$2"
          local src_dir="$3"
          local log_file="$4"

          echo "[$(date '+%Y-%m-%d %H:%M:%S')] Syncing to $remote:$remote_path" >> "$log_file"
          if rsync -az \
            --filter=':- .gitignore' \
            --filter='- .git/' \
            "$src_dir/" "$remote:$remote_path/" >> "$log_file" 2>&1; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync completed" >> "$log_file"
          else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync failed with exit code $?" >> "$log_file"
          fi
        }

        sync_loop() {
          local remote="$1"
          local remote_path="$2"
          local src_dir="$3"
          local log_file="$4"

          echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting sync loop for $src_dir -> $remote:$remote_path" >> "$log_file"

          # Initial sync
          do_sync "$remote" "$remote_path" "$src_dir" "$log_file"

          # Watch for changes and sync using fswatch
          # -1 = exit after first event, --latency=0.5 = batch events within 500ms
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for changes..." >> "$log_file"
          while fswatch -1 --latency=0.5 --exclude='\.git' "$src_dir" >> "$log_file" 2>&1; do
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Change detected" >> "$log_file"
            do_sync "$remote" "$remote_path" "$src_dir" "$log_file"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for changes..." >> "$log_file"
          done
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] fswatch exited, sync loop ending" >> "$log_file"
        }

        cmd_start() {
          local remote="$1"
          local remote_path="$2"
          local src_dir
          src_dir="$(pwd)"

          if [[ -z "$remote_path" ]]; then
            remote_path="$src_dir"
          fi

          local watch_name
          watch_name="$(echo "$src_dir" | tr '/' '_')"
          local pid_file="$STATE_DIR/$watch_name.pid"
          local info_file="$STATE_DIR/$watch_name.info"
          local log_file="$LOG_DIR/$watch_name.log"

          if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
            echo "Already syncing $src_dir"
            exit 1
          fi

          # Start sync loop in background with nohup, preserving PATH for nix binaries
          nohup bash -c "export PATH='$PATH'; $(declare -f do_sync sync_loop); sync_loop '$remote' '$remote_path' '$src_dir' '$log_file'" </dev/null >> "$log_file" 2>&1 &
          local pid=$!
          disown "$pid"

          echo "$pid" > "$pid_file"
          echo "$src_dir -> $remote:$remote_path" > "$info_file"

          echo "Started syncing $src_dir -> $remote:$remote_path (pid: $pid)"
          echo "Logs: $log_file"
        }

        cmd_stop() {
          local remote="$1"
          local src_dir
          src_dir="$(pwd)"
          local watch_name
          watch_name="$(echo "$src_dir" | tr '/' '_')"

          if [[ -n "$remote" ]]; then
            # Stop specific sync for current directory
            local pid_file="$STATE_DIR/$watch_name.pid"
            if [[ -f "$pid_file" ]]; then
              local pid
              pid="$(cat "$pid_file")"
              if kill -0 "$pid" 2>/dev/null; then
                kill "$pid"
                echo "Stopped sync (pid: $pid)"
              fi
              rm -f "$pid_file" "$STATE_DIR/$watch_name.info"
            else
              echo "No active sync for $src_dir"
            fi
          else
            # Stop all syncs
            for pid_file in "$STATE_DIR"/*.pid; do
              [[ -f "$pid_file" ]] || continue
              local pid
              pid="$(cat "$pid_file")"
              if kill -0 "$pid" 2>/dev/null; then
                kill "$pid"
                echo "Stopped sync (pid: $pid)"
              fi
              rm -f "$pid_file"
            done
            rm -f "$STATE_DIR"/*.info
            echo "Stopped all syncs"
          fi
        }

        cmd_list() {
          local found=0
          for info_file in "$STATE_DIR"/*.info; do
            [[ -f "$info_file" ]] || continue
            local pid_file="''${info_file%.info}.pid"
            if [[ -f "$pid_file" ]]; then
              local pid
              pid="$(cat "$pid_file")"
              if kill -0 "$pid" 2>/dev/null; then
                echo "[pid $pid] $(cat "$info_file")"
                found=1
              else
                # Clean up stale files
                rm -f "$pid_file" "$info_file"
              fi
            fi
          done
          if [[ $found -eq 0 ]]; then
            echo "No active syncs"
          fi
        }

        cmd_logs() {
          local src_dir
          src_dir="$(pwd)"
          local watch_name
          watch_name="$(echo "$src_dir" | tr '/' '_')"
          local log_file="$LOG_DIR/$watch_name.log"

          if [[ -f "$log_file" ]]; then
            tail -f "$log_file"
          else
            echo "No logs found for $src_dir"
            exit 1
          fi
        }

        eval "$(docopts -h - : "$@" <<EOF
        slync - fswatch-based file synchronizer

        Usage:
          slync start <remote> [<remote_path>]
          slync stop [<remote>]
          slync list
          slync logs
          slync -h | --help

        Commands:
          start     Start syncing current directory to remote
          stop      Stop syncing (specific remote or all)
          list      List active sync sessions
          logs      Tail logs for current directory's sync

        Arguments:
          <remote>       Remote host (e.g., user@host)
          <remote_path>  Remote path (defaults to current directory path)
        EOF
        )"

        # shellcheck disable=SC2154 # variables set by docopts eval
        if [[ "$start" == "true" ]]; then
          cmd_start "$remote" "$remote_path"
        elif [[ "$stop" == "true" ]]; then
          cmd_stop "$remote"
        elif [[ "$list" == "true" ]]; then
          cmd_list
        elif [[ "$logs" == "true" ]]; then
          cmd_logs
        fi
      '';
    })
  ];
}
