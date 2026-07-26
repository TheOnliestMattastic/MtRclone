#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
readonly REMOTES=("dropbox")
readonly MOUNT_BASE_DIR="${HOME}"
readonly SERVICE_DIR="${HOME}/.config/systemd/user"
readonly SERVICE_FILE="${SERVICE_DIR}/MtRclone.service"
declare -a MOUNT_PIDS=()

# --- Functions ---
log() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

bootstrap_systemd() {
  if [[ "$(ps -o comm= -p "$PPID" 2>/dev/null)" == "systemd" ]]; then
    return 0
  fi

  if [ ! -f "$SERVICE_FILE" ]; then
    log "Systemd service file missing. Automating creation..."
    mkdir -p "$SERVICE_DIR"

    local script_path
    script_path=$(realpath "${BASH_SOURCE[0]}")

    cat <<EOF >"$SERVICE_FILE"
[Unit]
Description=Rclone auto-mounter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${script_path}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

    log "Service file injected at: ${SERVICE_FILE}"
    log "Reloading systemd user daemon and enabling service..."

    systemctl --user daemon-reload
    systemctl --user enable MtRclone.service

    log "Service permanently registered! It will run automatically on login."

    # ask user for immediate execution
    local response=""
    if [ -t 0 ]; then
      read -r -p "Would you like to hand execution off to systemd right now? (y/N): " response || true
    fi

    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      log "Handing off to systemd. Exiting current script instance..."
      systemctl --user start MtRclone.service
      exit 0
    fi
  else
    log "Service file already exists at ${SERVICE_FILE}. Skipping generation."
  fi
}

cleanup() {
  local exit_code=$?
  echo ""
  log "Shutting down and clearing mounts..."

  # loop through remotes to unmount
  for remote in "${REMOTES[@]}"; do
    local mount_point="${MOUNT_BASE_DIR}/${remote}"
    if mountpoint -q "$mount_point" 2>/dev/null; then
      log "Unmounting ${mount_point}..."
      fusermount3 -u "$mount_point" || fusermount -u "$mount_point" || umount "$mount_point"
    fi
  done

  for pid in "${MOUNT_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
    fi
  done

  log "Cleanup complete. Exiting with code ${exit_code}."
}

trap cleanup EXIT INT TERM

# --- Verification ---
if ! command -v rclone &>/dev/null; then
  log "[I AM ERROR] Rclone is not installed or not in PATH." >&2
  exit 1
fi

bootstrap_systemd

log "Starting cloud drive mounting process..."

# --- Core ---
for remote in "${REMOTES[@]}"; do
  mount_point="${MOUNT_BASE_DIR}/${remote}"

  # create dir if it doesn't exist
  if [ ! -d "$mount_point" ]; then
    log "Creating directory: ${mount_point}"
    mkdir -p "$mount_point"
  fi

  # veryify dir isn't already a mount point
  if mountpoint -q "$mount_point"; then
    log "[I AM ERROR] ${mount_point} is already mounted. Skipping."
    continue
  fi

  log "Mounting remote '${remote}' to '${mount_point}'..."

  # mount remote via rclone
  rclone mount "${remote}:" "$mount_point" \
    --vfs-cache-mode writes \
    --dir-cache-time 1h \
    --log-file="${HOME}/.rclone-${remote}.log" \
    --log-level INFO &

  # capture PID
  MOUNT_PIDS+=($!)
  sleep 1
done

log "All drives processed. Script keeping process alive to preserve traps."
log "Press [Ctrl+C] at any time to cleanly unmount and exit."

while true; do
  sleep 1
done
