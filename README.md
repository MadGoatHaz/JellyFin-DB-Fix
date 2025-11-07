# Jellyfin Database Repair Utility

This utility provides an automated solution for fixing common database corruption issues in Jellyfin, specifically the recurring error: `SQLite Error 11: 'database disk image is malformed'`.

This corruption typically affects the library indexing tables (BaseItems, BaseItemRepository) within the main configuration database (`jellyfin.db`), leading to failed library scans and server instability. This script rebuilds the database structure while preserving your user accounts, server settings, and library definitions.

---

## 🚀 Quick Fix Guide (For the Normal User)

### Prerequisites

1.  This script is designed for Linux installations (like Arch/Debian/Ubuntu) where Jellyfin runs as a system service under the `jellyfin` user.
2.  You must have `sudo` privileges to run this script.
3.  The `sqlite3` command-line tool must be installed on your system.

### How to Run the Fix

1.  **Navigate** to the `JellyFin DB Fix` folder in your terminal.
2.  **Execute the script** using `sudo`:

    ```bash
    sudo ./jellyfin_db_fix.sh
    ```

### What Happens Next?

*   The script will automatically stop the Jellyfin service, create a backup of your corrupted database in `~/JellyFin_DB_Backups/` (note: this is `/root/JellyFin_DB_Backups` when running with `sudo`), repair the database structure, and restart the service.
*   Once restarted, Jellyfin will automatically detect the missing library index data and perform a **full media library scan**. This scan should now complete successfully, resolving the original database error.
*   **If the corruption is too severe,** the script will pause and offer an option to perform a **FULL DATABASE RESET**. Choosing this option will delete the database entirely, forcing Jellyfin to start the initial setup wizard, requiring you to reconfigure your server and user accounts (but preserving your media files).

---

## ⚙️ Technical Deep Dive (For the Technically Minded)

### What the Script Fixes

The primary issue fixed is the physical corruption of the SQLite database file (`jellyfin.db`). This corruption prevents the database engine from safely reading or writing data, especially during complex library operations.

The script addresses this by performing a **database dump and re-import**:

1.  **Service Control:** Stops and restarts the `jellyfin` service using `systemctl`.
2.  **Safe Backup:** Creates a timestamped backup of the original corrupted file (`jellyfin.db`) in your home directory at `~/JellyFin_DB_Backups/`.
3.  **Repair Mechanism:** Executes `sqlite3 .dump` on the corrupted file. This command reads the entire database structure and data, ignoring the underlying physical corruption, and outputs it as clean SQL commands.
4.  **Rebuild:** Imports the clean SQL commands into a new file (`jellyfin.db.new`), effectively rebuilding the database from scratch with a pristine physical structure.
5.  **Journal Cleanup:** Removes any lingering SQLite journal files (`.db-shm` and `.db-wal`) associated with the old, corrupted database to ensure a clean start.
6.  **Permissions:** Corrects the file ownership using `sudo chown jellyfin:jellyfin` to prevent "readonly database" errors that commonly occur after manual file operations.

### Benefits of this Approach

This method is superior to simply deleting the database because it:

*   **Preserves Configuration:** All server settings, user accounts, custom display preferences, and API keys stored in the configuration tables are preserved.
*   **Clears Library Index:** Although the configuration is kept, the library index data (which was the source of the corruption) is safely rebuilt by the server upon restart.

### Irrecoverable Corruption Fallback

If the `sqlite3 .dump` command fails (Exit Code 1), it indicates that the corruption is so severe that even the configuration data cannot be reliably extracted. In this scenario, the script offers a fallback to delete the database entirely, allowing Jellyfin to start fresh and prompt the user for a complete server re-setup.