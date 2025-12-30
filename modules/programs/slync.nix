{ pkgs, ... }:

{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "slync";
      runtimeInputs = [ pkgs.docopts pkgs.watchman pkgs.rsync pkgs.git pkgs.jq ];
      text = ''
        # slync - Watchman-based file synchronizer
        #
        # Usage:
        #   slync start <remote> [<remote_path>]
        #   slync stop [<remote>]
        #   slync list
        #   slync -h | --help
        #
        # Commands:
        #   start     Start syncing current directory to remote
        #   stop      Stop syncing (specific remote or all)
        #   list      List active sync sessions
        #
        # Arguments:
        #   <remote>       Remote host (e.g., user@host)
        #   <remote_path>  Remote path (defaults to current directory path)

        STATE_DIR="''${HOME}/.local/state/slync"
        mkdir -p "$STATE_DIR"

        do_sync() {
          local remote="$1"
          local remote_path="$2"
          local src_dir="$3"

          rsync -az --delete \
            --filter=':- .gitignore' \
            --filter='- .git/' \
            "$src_dir/" "$remote:$remote_path/"
        }

        sync_loop() {
          local remote="$1"
          local remote_path="$2"
          local src_dir="$3"

          # Initial sync
          do_sync "$remote" "$remote_path" "$src_dir"

          # Watch for changes and sync
          while watchman-wait "$src_dir" > /dev/null 2>&1; do
            do_sync "$remote" "$remote_path" "$src_dir"
          done
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

          if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
            echo "Already syncing $src_dir"
            exit 1
          fi

          # Start watchman watch on the directory
          watchman watch "$src_dir" > /dev/null

          # Start sync loop in background
          sync_loop "$remote" "$remote_path" "$src_dir" &
          local pid=$!

          echo "$pid" > "$pid_file"
          echo "$src_dir -> $remote:$remote_path" > "$info_file"

          echo "Started syncing $src_dir -> $remote:$remote_path (pid: $pid)"
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
              watchman watch-del "$src_dir" > /dev/null 2>&1 || true
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
            # Clean up all watchman watches for slync
            watchman watch-list | jq -r '.roots[]' 2>/dev/null | while read -r dir; do
              watchman watch-del "$dir" > /dev/null 2>&1 || true
            done
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

        eval "$(docopts -h - : "$@" <<EOF
        slync - Watchman-based file synchronizer

        Usage:
          slync start <remote> [<remote_path>]
          slync stop [<remote>]
          slync list
          slync -h | --help

        Commands:
          start     Start syncing current directory to remote
          stop      Stop syncing (specific remote or all)
          list      List active sync sessions

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
        fi
      '';
    })
  ];
}
