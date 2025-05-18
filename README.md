# DB Drive Backups

Automated system for backing up PostgreSQL databases and storing them on Google Drive.

## Features

- Automatically creates PostgreSQL database backups
- Uploads backups to Google Drive
- Sends email notifications
- Manages backup retention (removes old backups)
- Preserves monthly backups for long-term storage
- Automatic crontab scheduling

## Requirements

- PostgreSQL
- rclone
- msmtp
- Google Drive account

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/ATERCATES/dbDriveBackups.git
   cd dbDriveBackups
   ```

2. Run the configuration script:
   ```bash
   ./configure.sh
   ```

3. Configure environment variables:
   ```bash
   cp .env.template .env
   nano .env  # Edit with your data
   ```

## Usage

Run the backup script manually:
```bash
./backupdb.sh
```

### Scheduling Backups

When running the configuration script, you'll be asked if you want to set up automated backups with crontab. 
You can choose from several scheduling options:

- Daily backups (at a specific time)
- Weekly backups (Sunday)
- Monthly backups (1st day of the month)
- Custom schedule

Alternatively, you can manually configure it as a scheduled task with cron:
```bash
# Example: run every day at 2:00 AM
0 2 * * * cd /path/to/dbDriveBackups && ./backupdb.sh >> /path/to/dbDriveBackups/logs/cron.log 2>&1
```

## Structure

```
dbDriveBackups/
├── .env.template    # Environment variables template
├── .env             # Environment variables file (not included in git)
├── backupdb.sh      # Main backup script
├── configure.sh     # Initial configuration script
├── logs/            # Log files directory
├── LICENSE          # Project license
└── README.md        # Documentation
```

## License

This project is licensed under the terms of the MIT License. See the [LICENSE](LICENSE) file for details.
