#!/bin/bash
#
# Database Backup to Google Drive
# Performs PostgreSQL backups and stores them on Google Drive
# 
# Version: 1.0.2
#

# Set secure configuration for the script
set -euo pipefail
IFS=$'\n\t'

# Function to send email via msmtp with MIME headers
send_email() {
    local subject="$1"
    local body="$2"
    {
        echo "Subject: $subject"
        echo "To: $ADMIN_EMAIL"
        echo "From: Backup System <$ADMIN_EMAIL>"
        echo "Content-Type: text/plain; charset=utf-8"
        echo
        echo -e "$body"
    } | msmtp "$ADMIN_EMAIL"
}

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message"
    
    # Also log to a file with absolute path
    echo "[$timestamp] [$level] $message" >> "${LOG_FILE}"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    source "${SCRIPT_DIR}/.env"
else
    echo "ERROR: Environment file .env not found. Copy .env.template to .env and configure it."
    exit 1
fi

# CONFIGURATION
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
ADMIN_EMAIL="$ADMIN_EMAIL"
export PGPASSWORD="$DB_PASSWD"

# Set backup retention days from env or default
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}

# Date and names
DATE=$(date +%F)
FILE_NAME="${DB_NAME}_${DATE}.pgdump"  # Changed extension from .tar to .pgdump to reflect actual format
LOCAL_PATH="/tmp/${FILE_NAME}"
BACKUP_DIR=${BACKUP_DIR:-"dbBackups"}
MONTHLY_BACKUP_DIR=${BACKUP_DIR_MONTHLY:-"dbBackups/monthly"}
REMOTE_NAME=${REMOTE_NAME:-"gdrive"}

# Log directory
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"

# Log file with absolute path
LOG_FILE="${LOG_DIR}/backup_$(date +%Y-%m-%d).log"

log_message "INFO" "Starting backup of $DB_NAME"

# Create backup using PostgreSQL's custom format
log_message "INFO" "Creating local backup at $LOCAL_PATH"
if ! pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Fc -f "$LOCAL_PATH"; then
    log_message "ERROR" "Error creating backup of database $DB_NAME"
    send_email "❌ Backup ERROR [$DATE]" "❌ Error creating backup of database $DB_NAME on $DATE"
    exit 1
fi

# Upload daily copy to Google Drive (general directory)
log_message "INFO" "Uploading copy to Google Drive: $BACKUP_DIR/$FILE_NAME"
if ! rclone copy "$LOCAL_PATH" "$REMOTE_NAME:${BACKUP_DIR}/"; then
    log_message "ERROR" "Could not upload backup $FILE_NAME to Google Drive"
    send_email "❌ Upload Error [$DATE]" "❌ Could not upload backup $FILE_NAME to Google Drive"
    exit 1
fi

# If it's the 1st of the month, also upload to monthly directory
if [ "$(date +%d)" == "01" ]; then
    log_message "INFO" "Today is the 1st of the month, saving monthly backup"
    rclone copy "$LOCAL_PATH" "$REMOTE_NAME:${MONTHLY_BACKUP_DIR}/"
    MONTHLY_SIZE=$(du -h "$LOCAL_PATH" | cut -f1)
fi

# Delete old copies (older than retention days) from Google Drive
FILES_DELETED=""
RETENTION_DATE=$(date -d "$BACKUP_RETENTION_DAYS days ago" +%F)
log_message "INFO" "Looking for copies older than $RETENTION_DATE to delete"
DAILY_BACKUPS=$(rclone ls "$REMOTE_NAME:${BACKUP_DIR}/" | awk '{print $2}')

# Function to extract date from filename
get_date_from_filename() {
    echo "$1" | grep -oP '\d{4}-\d{2}-\d{2}'
}

for file in $DAILY_BACKUPS; do
    FILE_DATE=$(get_date_from_filename "$file")
    if [[ -n "$FILE_DATE" && "$FILE_DATE" < "$RETENTION_DATE" ]]; then
        log_message "INFO" "Deleting old backup: $file"
        rclone delete "$REMOTE_NAME:${BACKUP_DIR}/${file}" || true
        # We use || true to prevent script termination due to set -e
        if [[ $? -eq 0 ]]; then
            FILES_DELETED+="${file}\n"
        fi
    fi
done

# Size of created backup
BACKUP_SIZE=$(du -h "$LOCAL_PATH" | cut -f1)

# Create email message
MESSAGE="✅ Backup successfully completed.

🔹 File: $FILE_NAME
📁 Location: Google Drive - $BACKUP_DIR/
📏 Local size: $BACKUP_SIZE
📝 Format: Custom PostgreSQL format (allows selective table restoration)"

if [ "$(date +%d)" == "01" ]; then
    MESSAGE+="

📤 Also copied to monthly directory:
$MONTHLY_BACKUP_DIR/$FILE_NAME ($MONTHLY_SIZE)"
fi

if [ -n "$FILES_DELETED" ]; then
    MESSAGE+="

🧹 Files deleted (older than $BACKUP_RETENTION_DAYS days):
$FILES_DELETED"
fi

# Send email
log_message "INFO" "Sending email notification to $ADMIN_EMAIL"
send_email "✅ Backup OK [$DATE]" "$MESSAGE"

# Delete local copy
log_message "INFO" "Deleting temporary local copy $LOCAL_PATH"
rm "$LOCAL_PATH"

log_message "INFO" "Backup completed successfully"
