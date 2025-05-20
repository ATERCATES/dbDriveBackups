#!/bin/bash
#
# Initial configuration for the backup system
# Configures necessary tools for backing up to Google Drive
#
# Version: 1.0.2
#

set -euo pipefail
IFS=$'\n\t'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No color

REMOTE_NAME="gdrive"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_info() {
    echo -e "${BLUE}==> $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ ERROR: $1${NC}" >&2
}

prompt_input() {
    local prompt_msg="$1"
    local var_name="$2"
    local silent="${3:-false}"

    if [[ $silent == true ]]; then
        read -rsp "$prompt_msg: " input_var
        echo
    else
        read -rp "$prompt_msg: " input_var
    fi

    # Export variable for external use
    printf -v "$var_name" '%s' "$input_var"
}

check_dependencies() {
    print_info "Checking dependencies..."
    
    local missing_deps=()
    for cmd in pg_dump rclone msmtp; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_info "Missing the following dependencies: ${missing_deps[*]}"
        return 1
    else
        print_success "All required dependencies are installed"
        return 0
    fi
}

install_dependencies() {
    print_info "Updating repositories and installing required dependencies (rclone, msmtp, postgresql-client)..."
    sudo apt update
    sudo apt install -y rclone msmtp postgresql-client
    
    if check_dependencies; then
        print_success "Dependencies installed successfully"
    else
        print_error "Error installing dependencies"
        exit 1
    fi
}

configure_rclone() {
    print_info "Configuring rclone with Google Drive..."

    if rclone listremotes | grep -qw "$REMOTE_NAME"; then
        print_info "Remote '$REMOTE_NAME' already exists, skipping configuration"
    else
        print_info "Configuring Google Drive..."
        print_info "A browser window will open to authorize access."
        print_info "Follow the instructions on screen."
        
        if rclone config create "$REMOTE_NAME" drive scope=drive; then
            print_success "Rclone successfully configured with remote '$REMOTE_NAME'"
        else
            print_error "Error configuring rclone"
            exit 1
        fi
    fi

    print_info "Creating folders in Google Drive..."
    rclone mkdir "$REMOTE_NAME:dbBackups"
    rclone mkdir "$REMOTE_NAME:dbBackups/monthly"
    print_success "Folders 'dbBackups' and 'dbBackups/monthly' created in Google Drive"
}

configure_msmtp() {
    print_info "Configuring msmtp for email sending..."

    prompt_input "Enter your email address" EMAIL
    prompt_input "Enter your application password" APPKEY true
    APPKEY="${APPKEY// /}"

    MSMPTRC_PATH="$HOME/.msmtprc"

    cat > "$MSMPTRC_PATH" <<EOF
defaults
auth           on
tls            on
tls_starttls   on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account gmail
host smtp.gmail.com
port 587
user $EMAIL
from $EMAIL
password "$APPKEY"

account default : gmail
EOF

    chmod 600 "$MSMPTRC_PATH"
    print_success "msmtp successfully configured in $MSMPTRC_PATH"
}

configure_env_file() {
    print_info "Configuring environment variables file..."
    
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        print_info "An .env file already exists. Do you want to overwrite it? (y/n)"
        read -r choice
        if [[ ! "$choice" =~ ^[Yy]$ ]]; then
            print_info "Keeping existing .env file"
            return
        fi
    fi
    
    prompt_input "Enter database name" DB_NAME
    prompt_input "Enter database user" DB_USER
    prompt_input "Enter database host (default: localhost)" DB_HOST
    DB_HOST=${DB_HOST:-localhost}
    prompt_input "Enter database port (default: 5432)" DB_PORT
    DB_PORT=${DB_PORT:-5432}
    prompt_input "Enter database password" DB_PASSWD true
    
    cat > "$SCRIPT_DIR/.env" <<EOF
# Database Configuration
DB_NAME="$DB_NAME"
DB_USER="$DB_USER"
DB_HOST="$DB_HOST"
DB_PORT="$DB_PORT"
DB_PASSWD="$DB_PASSWD"
ADMIN_EMAIL="$EMAIL"

# Backup Configuration
BACKUP_RETENTION_DAYS="7"
REMOTE_NAME="gdrive"
BACKUP_DIR="dbBackups"
BACKUP_DIR_MONTHLY="dbBackups/monthly"
EOF
    
    chmod 600 "$SCRIPT_DIR/.env"
    print_success "Environment file .env configured successfully"
}

check_script_permissions() {
    print_info "Verifying script permissions..."
    
    if [[ ! -x "$SCRIPT_DIR/backupdb.sh" ]]; then
        print_info "Setting execution permissions for backupdb.sh"
        chmod +x "$SCRIPT_DIR/backupdb.sh"
    fi
    
    print_success "Script permissions verified"
}

create_log_directory() {
    print_info "Creating log directory..."
    
    mkdir -p "$SCRIPT_DIR/logs"
    
    print_success "Log directory created"
}

configure_crontab() {
    print_info "Setting up automated backups with crontab..."
    
    prompt_input "Do you want to set up a scheduled backup task? (y/n)" SETUP_CRON
    
    if [[ ! "$SETUP_CRON" =~ ^[Yy]$ ]]; then
        print_info "Skipping crontab configuration"
        return
    fi
    
    echo "Select a schedule option:"
    echo "1) Daily at 2:00 AM (recommended)"
    echo "2) Daily at a specific time"
    echo "3) Weekly (Sunday at 2:00 AM)"
    echo "4) Monthly (1st day at 2:00 AM)"
    echo "5) Custom schedule"
    
    prompt_input "Select an option (1-5)" SCHEDULE_OPTION
    
    case "$SCHEDULE_OPTION" in
        1)
            CRON_SCHEDULE="0 2 * * *"
            SCHEDULE_DESC="Daily at 2:00 AM"
            ;;
        2)
            prompt_input "Enter the hour (0-23)" HOUR
            CRON_SCHEDULE="0 $HOUR * * *"
            SCHEDULE_DESC="Daily at $HOUR:00"
            ;;
        3)
            CRON_SCHEDULE="0 2 * * 0"
            SCHEDULE_DESC="Weekly on Sunday at 2:00 AM"
            ;;
        4)
            CRON_SCHEDULE="0 2 1 * *"
            SCHEDULE_DESC="Monthly on the 1st at 2:00 AM"
            ;;
        5)
            print_info "Enter a custom crontab schedule:"
            print_info "Format: minute(0-59) hour(0-23) day(1-31) month(1-12) weekday(0-6, 0=Sunday)"
            print_info "Examples:"
            print_info "  Every day at 3:30 PM: 30 15 * * *"
            print_info "  Every Monday at 9:00 AM: 0 9 * * 1"
            prompt_input "Enter custom schedule" CRON_SCHEDULE
            SCHEDULE_DESC="Custom: $CRON_SCHEDULE"
            ;;
        *)
            print_error "Invalid option"
            return
            ;;
    esac
    
    CRON_COMMAND="$CRON_SCHEDULE cd $SCRIPT_DIR && ./backupdb.sh >> $SCRIPT_DIR/logs/cron.log 2>&1"
    
    print_info "Adding the following cron job:"
    print_info "$SCHEDULE_DESC"
    print_info "$CRON_COMMAND"
    
    prompt_input "Proceed? (y/n)" CONFIRM
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Skipping crontab configuration"
        return
    fi
    
    # Get existing crontab
    TEMP_CRON=$(mktemp)
    crontab -l > "$TEMP_CRON" 2>/dev/null || true
    
    # Check if entry already exists
    if grep -q "backupdb.sh" "$TEMP_CRON"; then
        print_info "A backup job already exists in crontab. Do you want to replace it? (y/n)"
        read -r choice
        if [[ ! "$choice" =~ ^[Yy]$ ]]; then
            print_info "Keeping existing crontab entry"
            rm "$TEMP_CRON"
            return
        fi
        # Remove existing backup job
        grep -v "backupdb.sh" "$TEMP_CRON" > "${TEMP_CRON}.new"
        mv "${TEMP_CRON}.new" "$TEMP_CRON"
    fi
    
    # Add new cron job
    echo "# DB Drive Backups - $SCHEDULE_DESC" >> "$TEMP_CRON"
    echo "$CRON_COMMAND" >> "$TEMP_CRON"
    
    # Install new crontab
    if crontab "$TEMP_CRON"; then
        print_success "Crontab configured successfully"
    else
        print_error "Failed to configure crontab"
    fi
    
    # Clean up
    rm "$TEMP_CRON"
}

main() {
    print_info "Starting DB Drive Backups configuration..."
    
    if ! check_dependencies; then
        install_dependencies
    fi
    
    configure_rclone
    configure_msmtp
    configure_env_file
    check_script_permissions
    create_log_directory
    configure_crontab
    
    print_success "Configuration completed successfully!"
    print_info "You can now run the backup script with: ./backupdb.sh"
    print_info "Consider adding it to crontab for automatic executions:"
    echo "0 2 * * * cd $SCRIPT_DIR && ./backupdb.sh"
}

main "$@"
