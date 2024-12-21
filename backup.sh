#!/bin/bash

# Global HTTP_ENDPOINT variable
HTTP_ENDPOINT="https://api.pushover.net/1/messages.json?token=a66k6nh2eoxvthpqu3rah6jwq7sq3b"

# Progress function to display messages
function show_progress {
    echo -e "\n[INFO] $1"
}

# Send notification to phone
function send_notification {
    local title="$1"
    local body="$2"

    # URL encode parameters
    title=$(printf "%s" "$title" | jq -s -R -r @uri)
    body=$(printf "%s" "$body" | jq -s -R -r @uri)

    # Append query parameters to the global HTTP_ENDPOINT
    local FINAL_HTTP_ENDPOINT="$HTTP_ENDPOINT&title=$title&body=$body"

    # Make the HTTP GET request
    curl -X GET "$FINAL_HTTP_ENDPOINT"
}

# Record the start time
start_time=$SECONDS

# Define source and destination paths
SOURCE_DIR="/opt/docker/"
DESTINATION_DIR="/mnt/archive/docker_backup"
BACKUP_NAME="docker-$(date +"%m_%d_%Y")"

# Check if the destination directory exists, create it if not
if [ ! -d "$DESTINATION_DIR/$BACKUP_NAME" ]; then
    mkdir -p "$DESTINATION_DIR/$BACKUP_NAME"
fi

# Redirect all output to a log file
exec > "$DESTINATION_DIR/$BACKUP_NAME/log.txt" 2>&1

# Stop Docker containers
show_progress "Stopping Docker containers..."
send_notification "Starting Docker Backup" "Docker backup started. Stopping all Docker containers."
docker stop $(docker ps -q)

# Sleep for 20 seconds to allow containers to stop gracefully
sleep 20s

# Record the start time for the backup
backup_start_time=$SECONDS

# Backup Docker volumes
show_progress "Backing up Docker volumes..."
if rsync -avhz --delete --exclude "_data/mysql.sock" --exclude "backingFsBlockDev"  "$SOURCE_DIR" "$DESTINATION_DIR/$BACKUP_NAME"; then
    # Record the end time for the backup
    backup_end_time=$SECONDS

    # Calculate the duration of the backup
    backup_duration=$((backup_end_time - backup_start_time))

    # Example HTTP GET request on successful backup
    TITLE="Docker Backup successfully completed"
    CURRENT_TIME=$(date +"%H:%M:%S")

    BODY="Docker has been backed up to <> at $CURRENT_TIME."
    BODY+=" Backup duration: ${backup_duration} seconds."

    # Send notification
    send_notification "$TITLE" "$BODY"
else
    # If the backup fails, send an error message in the HTTP GET request
    ERROR_TITLE="Docker Backup Failed"
    ERROR_BODY="There was an error in the Docker backup process."

    # Send notification
    send_notification "$ERROR_TITLE" "$ERROR_BODY"
fi

# Start Docker containers (regardless of backup success or failure)
show_progress "Starting Docker containers..."
docker start $(docker ps -q -a)
send_notification "Docker containers started" "Docker containers are back online"

# Sleep for another 20 seconds
sleep 20s

# Remove old backups (older than 10 days)
show_progress "Removing old backups..."
deleted_backups=$(find "$DESTINATION_DIR" -maxdepth 1 -type d -name "docker-*" -ctime +10 -exec rm -rf {} \; -print | wc -l)

# Example HTTP GET request on successful old backup removal
CURRENT_TIME_BACKUP_REMOVAL=$(date +"%H:%M:%S")
if [ "$deleted_backups" -eq 0 ]; then
    # No backups were removed
    TITLE_BACKUP_REMOVAL="No Backups Deleted"
    BODY_BACKUP_REMOVAL="No backups were removed today  as there are none older than 10 days."
else
    # Backups were removed
    TITLE_BACKUP_REMOVAL="$deleted_backups backups deleted"
    BODY_BACKUP_REMOVAL="$deleted_backups backups have been deleted at $CURRENT_TIME_BACKUP_REMOVAL."
fi

show_progress "$BODY_BACKUP_REMOVAL"

# Send notification
send_notification "$TITLE_BACKUP_REMOVAL" "$BODY_BACKUP_REMOVAL"

# Record the end time
end_time=$SECONDS

# Calculate the total duration
total_duration=$((end_time - start_time))

# Display total duration
show_progress "Script completed. Total duration: ${total_duration} seconds."
