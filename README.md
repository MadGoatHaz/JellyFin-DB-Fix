# Jellyfin Database Repair Utility

A focused repair tool for malformed or physically corrupted `jellyfin.db` databases, such as `SQLite Error 11: 'database disk image is malformed'`, while preserving valid configuration wherever possible.

This script rebuilds the database file using a `sqlite3 .dump` / `.read` pipeline instead of blindly deleting it, aiming to:

- Preserve: user accounts, server settings, library definitions, API keys, and other configuration data.
- Allow Jellyfin to safely rebuild: library index and scan state on next startup.

---

## Important Warnings / Read First

- This script directly operates on the core Jellyfin database at `/var/lib/jellyfin/data/jellyfin.db`.
- Always run it with care and read this document fully before use.

Key points:

- Compatibility:
  - Designed for Jellyfin 10.x.
  - Primarily developed and tested on later 10.11.x versions.
  - Uses `sqlite3 .dump` at the file level, so it is schema-agnostic and not tightly coupled to specific Jellyfin versions.
  - Relevant for 10.10.7 as a pre-migration check before the EF Core-based schema changes in 10.11.0.
- Use cases:
  - Recover from `jellyfin.db` corruption (e.g., SQLite Error 11, malformed disk image, broken library index tables).
  - Pre-migration repair on 10.10.7 before upgrading to 10.11.0 to reduce risk of migration failures.
- Backups and safety:
  - The script automatically creates a timestamped backup of the original database at:
    - `~/JellyFin_DB_Backups/` (under `sudo`, this resolves to `/root/JellyFin_DB_Backups`).
  - Media files are never deleted by this script.
  - Strongly recommended: before major upgrades or migrations, manually back up the entire `/var/lib/jellyfin/data/` directory to an independent location.

If you are not comfortable restoring from backups or reconfiguring Jellyfin, review this README carefully before proceeding.

---

## Quick Start

### Prerequisites

- Linux environment (e.g., Debian/Ubuntu/Arch) with Jellyfin installed as a system service.
- Jellyfin service running as the `jellyfin` user (default packaged installs).
- `sudo` privileges.
- `sqlite3` command-line tool installed and available in `PATH`.

### Run the Repair

From the cloned repository directory:

```bash
cd "JellyFin DB Fix"
sudo ./jellyfin_db_fix.sh
```

Defaults are:

- Database path: `/var/lib/jellyfin/data/jellyfin.db`
- Service name: `jellyfin`
- Service control via: `systemctl`

Custom installations:

- If your Jellyfin instance uses a different service name, user, or data path, review and adjust the variables at the top of [`jellyfin_db_fix.sh`](JellyFin DB Fix/jellyfin_db_fix.sh:17) before running.

### What the Script Does (At a Glance)

In order:

1. Stops the Jellyfin service using `systemctl stop jellyfin`.
2. Creates `~/JellyFin_DB_Backups/` if needed.
3. Copies the existing `jellyfin.db` into a timestamped backup file in that directory.
4. Runs `sqlite3` with `.dump` against the existing `jellyfin.db` and writes the output to a temporary SQL file.
5. Creates a new clean database file and imports the dumped SQL (`.read`) into it.
6. Swaps the old database file for the rebuilt one.
7. Removes stale SQLite journal files: `.db-shm` and `.db-wal`.
8. Fixes ownership on the new database (and data directory as needed) using `chown jellyfin:jellyfin` to avoid permission issues.
9. Starts the Jellyfin service using `systemctl start jellyfin`.
10. Cleans up temporary files.

On next startup, Jellyfin will:

- Detect and rebuild any missing or invalid library index data.
- Perform a fresh media library scan against a structurally healthy database.

---

## Details / How It Works

### Core Repair Mechanism

The script implements a conservative database repair workflow:

- Service control:
  - Stops Jellyfin before touching `jellyfin.db` to avoid concurrent writes.
  - Restarts Jellyfin after the repair via [`cleanup_and_restart()`](JellyFin DB Fix/jellyfin_db_fix.sh:31), which calls `systemctl start jellyfin`.
- Safe backup:
  - Ensures a backup directory exists at `"$HOME/JellyFin_DB_Backups"` and writes:
    - `jellyfin.db.corrupted.<timestamp>.bak`
  - Copy is performed with `sudo cp` to handle permissions.
- Dump and rebuild:
  - Executes:

    ```bash
    sudo sqlite3 "$DB_FULL_PATH" ".dump" > "$TEMP_SQL_FILE"
    ```

  - Creates a new database:

    ```bash
    sudo sqlite3 "$NEW_DB_FILE" ".read $TEMP_SQL_FILE"
    ```

  - This process:
    - Reads logical schema and data,
    - Discards low-level file corruption,
    - Re-emits clean SQL to reconstruct the database.
- Swap and cleanup:
  - Moves the original `jellyfin.db` aside (suffix `.corrupted_old`).
  - Moves the rebuilt file into place as `jellyfin.db`.
  - Deletes old journal files:
    - `$DB_FULL_PATH-shm`
    - `$DB_FULL_PATH-wal`
- Permissions:
  - Runs `chown jellyfin:jellyfin` on the repaired database (and, in full reset, on the data directory) so Jellyfin can read/write normally.

### Why This Is Better Than Deleting the DB

Compared to manually deleting `jellyfin.db`:

- Preserves:
  - User accounts.
  - Server configuration and preferences.
  - Library definitions and paths.
  - API keys and other critical configuration tables.
- Allows:
  - Jellyfin to rebuild the heavy library index data safely on next start.
- Minimizes:
  - Risk of unnecessary full reconfiguration.
  - Downtime due to misconfiguration introduced by starting from scratch.

This approach is intentionally schema-agnostic at the SQLite file level and is compatible with Jellyfin 10.x installations that use the standard `jellyfin.db` layout, including migrations such as the EF Core transition in 10.11.0, provided the underlying data is logically dumpable.

---

## Severe Corruption / Full Reset Behavior

When corruption is extreme:

- If the `sqlite3 .dump` step fails (non-zero exit, e.g., Exit Code 1), the script:
  - Logs that the database may be too severely corrupted.
  - Invokes the interactive [`full_reset()`](JellyFin DB Fix/jellyfin_db_fix.sh:40) workflow.

Full reset workflow:

1. Prompts for explicit confirmation:
   - `"Are you sure you want to proceed with a full database reset? (y/N):"`
2. On confirmation:
   - Deletes the corrupted `jellyfin.db`.
   - Deletes associated journal files (`.db-shm`, `.db-wal`).
   - Fixes directory ownership for the Jellyfin data directory.
   - Restarts the Jellyfin service.
3. Effect:
   - Jellyfin starts as a fresh installation, showing the initial setup wizard.
   - All prior:
     - User accounts,
     - Server configuration,
     - Library definitions,
     - History and watch state
     are reset.
   - Media files on disk are not touched or removed.

If you decline the reset:

- The script aborts so you can attempt manual recovery.

---

## FAQ / Notes

- Q: Is this only for a specific Jellyfin version?
  - A: It is built around standard `jellyfin.db` usage and the `sqlite3 .dump` mechanism, so it is generally suitable for Jellyfin 10.x. It has been primarily validated on later 10.11.x but is also useful on 10.10.7 as a pre-migration repair step.
- Q: Does this delete or modify my media files?
  - A: No. It only operates on the Jellyfin database and related SQLite journal files.
- Q: What about custom installs (non-default paths/users)?
  - A: Defaults are:
    - DB path: `/var/lib/jellyfin/data/jellyfin.db`
    - Service: `jellyfin`
    - User/group: `jellyfin:jellyfin`
    If your environment differs, adjust the configuration variables at the top of [`jellyfin_db_fix.sh`](JellyFin DB Fix/jellyfin_db_fix.sh:17) accordingly before running.
- Q: Why is there both a backup and a `.corrupted_old` file?
  - A: The backup in `~/JellyFin_DB_Backups/` is your off-disk safety copy. The `.corrupted_old` file in-place is an immediate fallback and audit artifact.

---

## Acknowledgements

Special thanks to user "AfterShock" on Reddit for raising critical questions about:

- Version compatibility across Jellyfin 10.x.
- The 10.10.7 to 10.11.0 EF Core migration path.
- Practical concerns around corruption, migration safety, and repair strategies.

Their input helped refine the compatibility notes and documentation for this tool.