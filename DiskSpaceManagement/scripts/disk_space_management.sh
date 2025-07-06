#!/bin/bash
# ==============================================================================
# Unraid Disk Space Management Script
# ==============================================================================

# --- Environment ---
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --- Configuration ---
CONFIG_FILE="/boot/config/plugins/DiskSpaceManagement/settings.cfg"

# Set default values for all settings first.
THRESHOLD_GB="50"
DRY_RUN="true"
LOG_FILE="/var/log/diskspacemanagement.log"
MOVIE_DIRS="share/Movies"
TV_SHOW_DIRS="share/TV"
EXCLUDED_DISKS=""
NOTIFY="true"

# Load settings from the config file, which will overwrite the defaults if present.
if [ -f "$CONFIG_FILE" ];
then
    source "$CONFIG_FILE"
fi

# Reformat arrays from config, handling empty settings correctly.
if [ -n "$MOVIE_DIRS" ]; then
    IFS=',' read -r -a MOVIE_DIRS_ARRAY <<< "$MOVIE_DIRS"
else
    MOVIE_DIRS_ARRAY=()
fi

if [ -n "$TV_SHOW_DIRS" ]; then
    IFS=',' read -r -a TV_SHOW_DIRS_ARRAY <<< "$TV_SHOW_DIRS"
else
    TV_SHOW_DIRS_ARRAY=()
fi

if [ -n "$EXCLUDED_DISKS" ]; then
    IFS=',' read -r -a EXCLUDED_DISKS_ARRAY <<< "$EXCLUDED_DISKS"
else
    EXCLUDED_DISKS_ARRAY=()
fi

# --- Script Logic ---
LAST_MOVE_SIZE_GB=0
mkdir -p "$(dirname "$LOG_FILE")"

log_message() {
    local message
    message="$(date +'%Y-%m-%d %H:%M:%S') - $1"
    echo "$message"
}

send_notification() {
    if [ "$NOTIFY" = "true" ];
then
        /usr/local/emhttp/plugins/dynamix/scripts/notify -s "Disk Space Management" -d "$1"
    fi
}

is_disk_excluded() {
    local disk_to_check="$1"
    if [ ${#EXCLUDED_DISKS_ARRAY[@]} -eq 0 ]; then
        return 1
    fi
    local normalized_disk_to_check="${disk_to_check#/}"
    for excluded in "${EXCLUDED_DISKS_ARRAY[@]}";
    do
        local normalized_excluded="${excluded#/}"
        if [[ -z "${normalized_excluded// }" ]]; then
            continue
        fi
        if [[ "$normalized_disk_to_check" == "$normalized_excluded" ]];
        then
            return 0
        fi
    done
    return 1
}

get_folder_size_gb() {
    local folder_path="$1"
    local size_gb
    size_gb=$(du -sBG "$folder_path" 2>/dev/null | awk '{print $1}' | tr -d 'G')
    if ! [[ "$size_gb" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "0"
    else
        echo "$size_gb"
    fi
}

is_disk_almost_full() {
    local disk="$1"
    local simulated_freed_space=${2:-0}
    local current_free_space
    current_free_space=$(df -BG "$disk" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G')
    if ! [[ "$current_free_space" =~ ^[0-9]+([.][0-9]+)?$ ]]; then current_free_space=0; fi
    if ! [[ "$simulated_freed_space" =~ ^[0-9]+([.][0-9]+)?$ ]]; then simulated_freed_space=0; fi
    local comparison
    comparison=$(awk -v cur="$current_free_space" -v sim="$simulated_freed_space" -v thold="$THRESHOLD_GB" 'BEGIN { print (cur + sim < thold) }')
    if [[ "$comparison" -eq 1 ]];
    then
        return 0
    else
        return 1
    fi
}

find_target_disk() {
    local source_disk="$1"
    local best_disk=""
    local max_free_space=0
    while IFS= read -r line;
    do
        local disk_path
        local free_space_gb
        disk_path=$(echo "$line" | awk '{print $NF}')
        free_space_gb=$(echo "$line" | awk '{print $4}' | tr -d 'G')
        if ! [[ "$free_space_gb" =~ ^[0-9]+([.][0-9]+)?$ ]]; then continue; fi
        if [[ "$disk_path" == "$source_disk" ]];
        then
            continue
        fi
        if is_disk_excluded "$disk_path";
        then
            continue
        fi
        local is_greater
        is_greater=$(awk -v f1="$free_space_gb" -v f2="$max_free_space" 'BEGIN { print (f1 > f2) }')
        if [ "$is_greater" -eq 1 ];
        then
            max_free_space=$free_space_gb
            best_disk=$disk_path
        fi
    done < <(df -BG | grep '/mnt/disk[0-9]\+')
    echo "$best_disk"
}

move_folder_rsync() {
    local source_path="$1"
    local target_dir="$2"
    local source_folder_name
    source_folder_name=$(basename "$source_path")
    local full_target_path="$target_dir/$source_folder_name"
    LAST_MOVE_SIZE_GB=0
    if [[ ! -d "$target_dir" ]]; then
        log_message "Creating target directory: $target_dir"
        if [ "$DRY_RUN" = "false" ];
        then
            mkdir -p "$target_dir"
            chown nobody:users "$target_dir"
        fi
    fi
    local rsync_cmd="rsync -aH --remove-source-files \"$source_path/\" \"$full_target_path/\""
    if [ "$DRY_RUN" = "true" ];
    then
        local folder_size_gb
        folder_size_gb=$(get_folder_size_gb "$source_path")
        log_message "[DRY RUN] Would move: '$source_path' ($folder_size_gb GB) to '$full_target_path'"
        log_message "[DRY RUN] Would execute: $rsync_cmd"
        LAST_MOVE_SIZE_GB=$folder_size_gb
        return 0
    fi
    log_message "Preparing to move: '$source_path' to '$full_target_path'"
    log_message "Executing: $rsync_cmd"
    if eval "$rsync_cmd";
    then
        log_message "Successfully moved '$source_path' to '$full_target_path'"
        rm -rf "$source_path"
        return 0
    else
        log_message "ERROR: rsync failed to move '$source_path'. See rsync output above."
        send_notification "ERROR: rsync failed to move '$source_path'."
        return 1
    fi
}

# --- Main Execution ---
log_message "--- Disk Space Management script starting ---"
if [ "$DRY_RUN" = "true" ];
then
    START_MESSAGE="Dry run started. No files will be moved."
    log_message "*** DRY RUN MODE ENABLED *** No files will be moved."
else
    START_MESSAGE="Script run started."
fi
send_notification "Disk Space Management - $START_MESSAGE"

mounted_disks=$(df | grep '/mnt/disk[0-9]\+' | awk '{print $NF}' | sort)
for disk in $mounted_disks;
do
    if is_disk_excluded "$disk"; then
        log_message "Skipping excluded disk: $disk"
        continue
    fi
    if ! is_disk_almost_full "$disk"; then
        continue
    fi
    initial_free_space=$(df -BG "$disk" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G')
     if ! [[ "$initial_free_space" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        initial_free_space="N/A"
    fi
    log_message "Disk $disk is below the ${THRESHOLD_GB}GB threshold (initial space: ${initial_free_space}GB). Planning moves..."
    
    item_list=$(
        for dir in "${MOVIE_DIRS_ARRAY[@]}"; do
            find "$disk/$dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | while IFS= read -r -d '' folder; do
                echo "1|0|$folder|$dir"
            done
        done
        for dir in "${TV_SHOW_DIRS_ARRAY[@]}"; do
            find "$disk/$dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | while IFS= read -r -d '' folder; do
                seasons_count=$(find "$folder" -mindepth 1 -maxdepth 1 -type d | wc -l)
                echo "2|$seasons_count|$folder|$dir"
            done
        done
    )

    sorted_item_list=$(echo "$item_list" | sort -t'|' -k1,1n -k2,2n)
    
    if [[ -z "$sorted_item_list" ]];
    then
        log_message "No movable files found on $disk."
        continue
    fi
    
    simulated_freed_space_gb=0
    target_disk=$(find_target_disk "$disk")
    
    if [[ -z "$target_disk" ]];
    then
        log_message "No suitable target disk found for source $disk."
        continue
    fi
    log_message "Best target disk found: $target_disk"

    while IFS='|' read -r priority sort_key folder_path target_base_dir; do
        if ! is_disk_almost_full "$disk" "$simulated_freed_space_gb";
        then
            current_free_space=$(df -BG "$disk" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G')
            if ! [[ "$current_free_space" =~ ^[0-9]+([.][0-9]+)?$ ]]; then current_free_space=0; fi
            effective_space=$(awk -v cur="$current_free_space" -v sim="$simulated_freed_space_gb" 'BEGIN { print cur + sim }')
            log_message "Disk $disk is now above the threshold (effective space: ${effective_space}GB). Halting moves for this disk."
            break
        fi
        if [[ -z "$folder_path" ]];
        then continue; fi
        if [[ "$priority" -eq 2 ]];
        then
             log_message "Found TV show: '$(basename "$folder_path")' with $sort_key seasons."
        fi
        if [ "$DRY_RUN" = "true" ];
        then
            move_folder_rsync "$folder_path" "$target_disk/$target_base_dir"
            size_moved=$LAST_MOVE_SIZE_GB
            simulated_freed_space_gb=$(awk -v cur="${simulated_freed_space_gb:-0}" -v moved="${size_moved:-0}" 'BEGIN { print cur + moved }')
        else
            if ! move_folder_rsync "$folder_path" "$target_disk/$target_base_dir"; then
                log_message "A real move failed. Stopping further moves from $disk."
                break
            fi
        fi
    done <<< "$sorted_item_list"
done
log_message "--- Disk Space Management script finished ---"
send_notification "Disk Space Management script run finished."
