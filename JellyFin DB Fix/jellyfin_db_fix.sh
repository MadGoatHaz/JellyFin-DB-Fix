#!/bin/bash

# =================================================================================
# Jellyfin Database Repair Script (jellyfin_db_fix.sh)
#
# This script attempts to fix severe SQLite corruption (like "database disk image
# is malformed") in the main Jellyfin configuration database (jellyfin.db)
# by performing a dump/re-import operation, which rebuilds the physical database
# structure while preserving user settings and library paths.
#
# IMPORTANT: This script requires 'sudo' privileges to stop/start the service,
# handle file permissions, and access the system-level database directory.
#
# Usage: sudo ./jellyfin_db_fix.sh
# =================================================================================

# --- Configuration ---
DB_PATH="/var/lib/jellyfin/data"
DB_FILE="jellyfin.db"
DB_FULL_PATH="$DB_PATH/$DB_FILE"
TEMP_SQL_FILE="/tmp/jellyfin_dump.$$.sql"
NEW_DB_FILE="$DB_PATH/$DB_FILE.new"
BACKUP_DIR="$HOME/JellyFin_DB_Backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/$DB_FILE.corrupted.$TIMESTAMP.bak"
JF_USER="jellyfin"
JF_GROUP="jellyfin"

# --- Functions ---

cleanup_and_restart() {
    echo "9. Starting Jellyfin service..."
    sudo systemctl start jellyfin
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to start Jellyfin service. Check logs for details."
        exit 1
    fi
}

full_reset() {
    echo "--------------------------------------------------------"
    echo "CRITICAL: Database dump failed. Proceeding with full configuration reset."
    echo "WARNING: This will delete all user settings, media library definitions, and history."
    echo "Jellyfin will start as if it were a brand new installation, requiring re-setup."
    read -r -p "Are you sure you want to proceed with a full database reset? (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "   - Deleting corrupted database file: $DB_FULL_PATH"
            sudo rm -f "$DB_FULL_PATH"
            echo "   - Deleting associated journal files."
            sudo rm -f "$DB_FULL_PATH-shm" "$DB_FULL_PATH-wal"
            echo "   - Fixing ownership of data directory."
            sudo chown -R "$JF_USER":"$JF_GROUP" "$DB_PATH"
            echo "Full database reset complete. Restarting Jellyfin now."
            cleanup_and_restart
            echo "Full reset completed. Please access Jellyfin Web UI to run initial setup wizard."
            exit 0
            ;;
        *)
            echo "Aborting full reset. Please investigate corruption manually."
            exit 1
            ;;
    esac
}

# --- Main Execution ---

echo "Starting Jellyfin Database Repair Process..."
echo "--------------------------------------------------------"

# 1. Stop Jellyfin Service
echo "1. Stopping Jellyfin service..."
sudo systemctl stop jellyfin
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to stop Jellyfin service. Aborting."
    exit 1
fi
echo "Service stopped."

# 2. Create local backup directory and move the original database there
echo "2. Creating local backup directory at $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

if [ -f "$DB_FULL_PATH" ]; then
    echo "   - Backing up current database to $BACKUP_FILE"
    sudo cp "$DB_FULL_PATH" "$BACKUP_FILE"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to copy database for backup. Check permissions for $DB_FULL_PATH. Aborting."
        exit 1
    fi
else
    echo "ERROR: Database file not found at $DB_FULL_PATH. Aborting."
    exit 1
fi

# 3. Dump the contents of the corrupted database to a clean SQL file
echo "3. Dumping database contents to temporary SQL file..."
if ! sudo sqlite3 "$DB_FULL_PATH" ".dump" > "$TEMP_SQL_FILE"; then
    echo "ERROR: Failed to dump database contents. The database may be too severely corrupted."
    full_reset
fi
echo "Dump successful."

# 4. Create a new database and import the clean SQL dump
echo "4. Importing dump into new clean database file ($NEW_DB_FILE)..."
sudo sqlite3 "$NEW_DB_FILE" ".read $TEMP_SQL_FILE"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to import SQL dump into new database. Aborting."
    exit 1
fi
echo "Import successful. New database created."

# 5. Replace the corrupted database with the new one
echo "5. Replacing corrupted database with the rebuilt file."
sudo mv "$DB_FULL_PATH" "$DB_FULL_PATH.corrupted_old"
sudo mv "$NEW_DB_FILE" "$DB_FULL_PATH"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to rename/replace database files. Aborting."
    exit 1
fi
echo "Database successfully replaced."

# 6. Remove old journal files (shm/wal)
echo "6. Removing old journal files (.db-shm, .db-wal) to ensure clean start."
sudo rm -f "$DB_FULL_PATH-shm" "$DB_FULL_PATH-wal"

# 7. Correct permissions on the new database file
echo "7. Correcting ownership and permissions to $JF_USER:$JF_GROUP."
sudo chown "$JF_USER":"$JF_GROUP" "$DB_FULL_PATH"
if [ $? -ne 0 ]; then
    echo "WARNING: Failed to correct ownership. Permissions errors may occur on restart."
fi

# 8. Cleanup temporary files
echo "8. Cleaning up temporary files."
rm -f "$TEMP_SQL_FILE"

# 9. Start Jellyfin Service
cleanup_and_restart

echo "--------------------------------------------------------"
echo "Database repair complete. Jellyfin service restarted."
echo "Original corrupted database backed up to: $BACKUP_FILE"
echo "Please verify functionality and run a full library scan via the Jellyfin web interface."