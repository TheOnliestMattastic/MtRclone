# MtRclone

A cloud drive automounting bash script using `rclone`.

> ⚠️ Pecaution: This repository is configured specifically for my personal workstation. It utilizes a curated, hardcoded list of cloud remotes mapped directly to the home directory. Either modify this script for your own environment and rclone config, or ensure that your rclone configuration matches the following names: `Dropbox`, `GoogleDrive`, and `OneDrive`.

## How to Run It

Ensure the script is executable, then execute it.

```bash
git clone https://github.com/TheOnliestMattastic/MtRclone.git
cd MtRclone
chmod +x MtRclone.sh
./MtRclone.sh
```
> Select `y` when prompted to  automatically hand execution off to systemd management.

One regestered, the entire mounting lifecycle is controlled via standard systemd user-space flags:

```bash
# Check status
systemctl --user status MtRclone.service

# Stop / unmount
systemctl --user stop MtRclone.service

# Start / mount
systemctl --user start MtRclone.service

# View service logs
journalctl --user -u MtRclone.service
```

## What Happens Under the Hood?

1. **Safety Net Initialization**: The script immediately registers a global lifecycle `trap` catching `EXIT`, `INT`, and `TERM` signals. If the script is mannually aborted (`Ctrl+C`), killed by the system, or errors out mid-run, the script loops through all mounts to cleanly tear them down using `fusermount3` (falling back to `umount`) and terminates dangling background `rclone` processes via tracked PIDs.
2. **Automated User-Space Systemd Provisioning**: The script is context-aware checking the enviornment variables `INVOCATION_ID` and `SYSTEMD_EXEC_PID` to determine if it is running manually or inside a systemd context.
3. **Mount Verification & VFS Cache Tuning**: Before mounting any storage layer, the script validates target existence (creating the directory if missing) and runs a safety verification check via `mountpoint -q`. Valid drives are launched into the background utilizing `--vfs-cache-mode writes` to ensure file compatibility with local desktop text editors.
4. **Isolated Logging Performance**: Each cloud drive creates its own localized log hidden within the home directory (e.g., `~/.rclone-dropbox.log`) to offer isolated, granular debugging at a glance.

