#!/bin/bash
# Version: 1.0.1

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables
if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
    echo "ERROR: Environment file .env not found."
    exit 1
fi
source "${SCRIPT_DIR}/.env"

# Setup basic configuration
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
export PGPASSWORD="$DB_PASSWD"
BACKUP_DIR=${BACKUP_DIR:-"dbBackups"}
MONTHLY_BACKUP_DIR=${BACKUP_DIR_MONTHLY:-"dbBackups/monthly"}
REMOTE_NAME=${REMOTE_NAME:-"gdrive"}

# Main restore function
restore_database() {
    local backup_file="$1"
    
    echo -e "\n🔄 Restoring database from backup file: $(basename "$backup_file")\n"
    
    # Check if database exists, create if not
    if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        echo -e "📦 Creating database $DB_NAME...\n"
        createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME" || {
            echo "❌ Failed to create database."
            return 1
        }
    else
        # Terminate existing connections
        echo -e "🔌 Disconnecting existing users...\n"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "
            SELECT pg_terminate_backend(pg_stat_activity.pid)
            FROM pg_stat_activity
            WHERE pg_stat_activity.datname = '$DB_NAME'
            AND pid <> pg_backend_pid();" postgres >/dev/null
    fi
    
    # Restore database using pg_restore
    echo "⏳ Restoring data... (this may take a while)"
    if pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" --clean --if-exists "$backup_file"; then
        echo -e "\n✅ Database restored successfully!"
        return 0
    else
        echo -e "\n❌ Failed to restore database."
        return 1
    fi
}

# Simple interactive menu
simple_restore_menu() {
    echo -e "\n📂 Select backup source:"
    echo "1) Daily backups"
    echo "2) Monthly backups"
    echo -e "q) Quit\n"
    
    read -rp "Enter choice [1/2/q]: " choice
    
    case "$choice" in
        1) backup_dir="$BACKUP_DIR" ;;
        2) backup_dir="$MONTHLY_BACKUP_DIR" ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
    
    echo -e "\n📋 Retrieving available backups...\n"
    
    # Get list of backups and save as array and use mapfile to read into array
    mapfile -t backups < <(rclone ls "$REMOTE_NAME:$backup_dir" | grep -E '\.pgdump$' | awk '{print $2}')

    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "❌ No backups found in $backup_dir"
        exit 0
    fi
    
    clear
    echo -e "\n📂 Available backups (${#backups[@]} found):"
    for i in "${!backups[@]}"; do
        echo "$((i+1))) ${backups[$i]}"
    done
    echo ""

    read -rp "Select backup to restore [1-${#backups[@]}]: " backup_num
    
    if [[ ! "$backup_num" =~ ^[0-9]+$ ]] || [ "$backup_num" -lt 1 ] || [ "$backup_num" -gt "${#backups[@]}" ]; then
        echo "❌ Invalid selection"
        exit 1
    fi
    
    selected_backup="${backups[$((backup_num-1))]}"

    echo -e "\n📥 Downloading backup: $selected_backup"
    
    temp_file="/tmp/$(basename "$selected_backup")"
    if ! rclone copy "$REMOTE_NAME:$backup_dir/$selected_backup" "/tmp/"; then
        echo "❌ Failed to download backup file."
        exit 1
    fi
    
    echo -e "\n⚠️  WARNING: This will overwrite the current database ($DB_NAME)!"
    read -rp "Are you sure you want to continue? (yes/no): " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        restore_database "$temp_file"
        rm -f "$temp_file"
    else
        echo "Restore canceled."
        rm -f "$temp_file"
    fi
}

# Main script
echo -e "\n📊 Database Restore Tool"
echo "=============================="

simple_restore_menu