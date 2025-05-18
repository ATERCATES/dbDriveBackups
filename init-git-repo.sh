#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Initializing Git repository for dbDriveBackups...${NC}"

# Initialize Git repository
git init

# Add all files except those in .gitignore (which includes .env)
git add .

# Create initial commit
git commit -m "Initial commit for dbDriveBackups"

# Make sure scripts are executable
chmod +x backupdb.sh
chmod +x configure.sh
chmod +x init-git-repo.sh

echo -e "${GREEN}Git repository initialized successfully!${NC}"
echo -e "${BLUE}Next steps:${NC}"
echo "1. Create your .env file (copy from .env.template)"
echo "2. Run ./configure.sh to set up dependencies"
echo "3. Run ./backupdb.sh to test the backup process"
echo "4. Set up a cron job for regular backups"
