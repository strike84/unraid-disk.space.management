#!/bin/bash
# ============================================================================
# Disk Space Management Script for Unraid
# ============================================================================
# Purpose: Automatically moves folders from disks that fall below a threshold
#          to disks with the most free space available.
#
# Author: strike
# Version: 2026.01.17
#
# HOW IT WORKS:
# 1. Reads configuration from /boot/config/plugins/DiskSpaceManagement/settings.cfg
# 2. Checks each disk to see if free space is below the threshold
# 3. For disks below threshold, moves folders from managed paths to the disk
#    with the most free space
# 4. Supports multiple sorting options: smallest, largest, alphabetical, newest, oldest
# 5. Tracks simulated free space during dry runs for accurate predictions
#
# CONFIGURATION FORMAT:
# - MANAGED_PATHS: path1:sort_type:excluded_disks|path2:sort_type:excluded_disks
# - THRESHOLD_GB: Minimum free space in GB before moves trigger
# - DRY_RUN: "true" = simulate only, "false" = actually move files
# - EXCLUDED_DISKS: Comma-separated list of disks to never move from/to
#
# SORTING OPTIONS:
# - smallest: Move smallest folders first (good for quick space gains)
# - largest: Move largest folders first (good for major rebalancing)
# - alphabetical: A-Z order
# - alphabetical_reversed: Z-A order
# - newest: Most recently modified first
# - oldest: Oldest modified first
# ============================================================================

# ============================================================================
# PROCESS MANAGEMENT
# ============================================================================
# These files track script state for the UI and allow graceful termination
RUN_FILE="/tmp/dsm.running"    # Indicates script is running
STOP_FILE="/tmp/dsm.stop"      # Created to signal script to stop gracefully

rm -f "$STOP_FILE"
echo $$ > "$RUN_FILE"
trap "rm -f $RUN_FILE" EXIT

# ============================================================================
# CONFIGURATION LOADING
# ============================================================================
CONFIG_FILE="/boot/config/plugins/DiskSpaceManagement/settings.cfg"

# Function: get_cfg
# Description: Extracts a configuration value from the settings file
# Parameters: $1 = configuration key name
# Returns: The value associated with the key (content between quotes)
get_cfg() { grep "^$1=" "$CONFIG_FILE" | cut -d'"' -f2; }

# Load configuration values with defaults
THRESHOLD_GB=$(get_cfg "THRESHOLD_GB")
DRY_RUN=$(get_cfg "DRY_RUN")
LOG_FILE=$(get_cfg "LOG_FILE")
NOTIFY=$(get_cfg "NOTIFY")
MANAGED_PATHS=$(get_cfg "MANAGED_PATHS")
EXCLUDED_DISKS=$(get_cfg "EXCLUDED_DISKS")

# Apply default values if configuration is missing
THRESHOLD_GB=${THRESHOLD_GB:-50}
DRY_RUN=${DRY_RUN:-true}
LOG_FILE=${LOG_FILE:-/var/log/diskspacemanagement.log}
NOTIFY=${NOTIFY:-true}

# ============================================================================
# LOGGING SETUP
# ============================================================================
# Create timestamped log that outputs to both file and a temp file for notifications
SCRIPT_START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
TEMP_LOG_FILE=$(mktemp)
trap 'rm -f "$TEMP_LOG_FILE"; rm -f "$RUN_FILE"' EXIT
exec > >(tee -a "$TEMP_LOG_FILE" >> "$LOG_FILE") 2>&1

# ============================================================================
# STATE TRACKING VARIABLES
# ============================================================================
# Associative arrays for tracking move statistics
declare -A MOVED_FROM_TO_GB      # Tracks GB moved between disk pairs (e.g., "disk1->disk2" = 5.2)
declare -A DISK_SIMULATED_FREE   # Tracks simulated free space after moves (for dry run accuracy)
declare -A SKIPPED_PATHS         # Tracks paths that were skipped due to errors

# Counters for statistics
TOTAL_MOVED_GB=0                 # Total GB moved in this session
MOVE_COUNT=0                     # Number of items moved
SIMULATED_PROCESSED_PATHS=""     # Pipe-delimited list of paths already processed (prevents loops)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Function: log_msg
# Description: Outputs a timestamped message to the log
# Parameters: $1 = message to log
log_msg() { echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"; }

# Function: get_free_gb
# Description: Gets the current free space of a disk in GB (base-10 units)
# Parameters: $1 = disk path (e.g., /mnt/disk1)
# Returns: Free space in GB with 4 decimal precision
get_free_gb() { df --output=avail -B1 "$1" | tail -n 1 | awk '{printf "%.4f", $1 / 1000000000}'; }

# Function: get_folder_size_gb
# Description: Calculates folder size in GB, with fallback for different du versions
# Parameters: $1 = folder path
# Returns: Folder size in GB with 4 decimal precision, or empty if unable to determine
# Note: Returns empty for empty folders or folders with permission issues
get_folder_size_gb() { 
    local raw_size
    # Try du -sb first (most accurate, shows apparent size)
    raw_size=$(du -sb "$1" 2>/dev/null | awk '{print $1}')
    if [ -z "$raw_size" ]; then
        # Fallback to du -sB1 if -sb fails (some systems)
        raw_size=$(du -sB1 "$1" 2>/dev/null | awk '{print $1}')
    fi
    if [ -n "$raw_size" ]; then
        echo "$raw_size" | awk '{printf "%.4f", $1 / 1000000000}'
    fi
}

# Function: check_path_safety
# Description: Prevents dangerous operations on /mnt/user paths
# Parameters: $1 = source path, $2 = destination path
# Exit: Exits script with error if unsafe path detected
# Rationale: Moving from /mnt/user can cause data loss due to FUSE caching issues
check_path_safety() {
    if [[ "$1" == *"/mnt/user/"* ]] || [[ "$2" == *"/mnt/user/"* ]]; then
        log_msg "CRITICAL SAFETY ERROR: /mnt/user detected. Aborting."
        exit 1
    fi
}

# Function: refresh_user_share
# Description: Triggers a FUSE cache refresh for the user share
# Parameters: $1 = destination path on disk
# Note: This works around a Unraid FUSE caching issue where moved files
#       may not immediately appear in the user share view
refresh_user_share() {
    local user_parent=$(dirname "$1" | sed 's|^/mnt/disk[0-9]*/|/mnt/user/|')
    [ -d "$user_parent" ] && touch "${user_parent}/.dsm_update" && rm "${user_parent}/.dsm_update"
}

# Function: find_target_disk
# Description: Finds the best destination disk for a move operation
# Parameters: $1 = source disk path, $2 = per-path exclusions (comma-separated)
# Returns: Path to the disk with most free space, or empty if none available
# Logic: Excludes source disk, globally excluded disks, and per-path excluded disks
find_target_disk() {
    local src="$1" local best="" local max=0 local exclusions="$2"
    for disk in /mnt/disk[0-9]*; do
        # Skip if: same as source, globally excluded, or per-path excluded
        [[ "$disk" == "$src" ]] || [[ ",$EXCLUDED_DISKS," == *",$disk,"* ]] || [[ ",$exclusions," == *",$disk,"* ]] && continue
        local free=${DISK_SIMULATED_FREE[$(basename "$disk")]}
        local is_greater=$(awk -v f1="$free" -v f2="$max" 'BEGIN { print (f1 > f2) }')
        if [ "$is_greater" -eq 1 ]; then max=$free; best=$disk; fi
    done
    echo "$best"
}

# ============================================================================
# INITIALIZATION
# ============================================================================
# Initialize simulated free space tracking for all disks
# This array stores the current free space (real or simulated after moves)
for disk in /mnt/disk[0-9]*; do DISK_SIMULATED_FREE[$(basename "$disk")]=$(get_free_gb "$disk"); done

# Parse managed paths from config (format: path:sort_type:excluded_disks)
IFS='|' read -r -a PATH_ARRAY <<< "$MANAGED_PATHS"

# Track if any disk was below threshold (for logging)
ANY_DISK_BELOW_THRESHOLD=false

log_msg "--- Disk Space Management: Execution Started ---"
log_msg "Threshold set to: ${THRESHOLD_GB}GB"
[ "$DRY_RUN" == "true" ] && log_msg "*** DRY RUN MODE ENABLED ***"

# ============================================================================
# MAIN DISK PROCESSING LOOP
# ============================================================================
# Iterate through all disks and check if they need space management
for disk in /mnt/disk[0-9]*; do
    D_NAME=$(basename "$disk")
    [[ ",$EXCLUDED_DISKS," == *",$disk,"* ]] && continue

    initial_free=$(get_free_gb "$disk")
    is_below=$(awk -v cur="$initial_free" -v thold="$THRESHOLD_GB" 'BEGIN { print (cur < thold) }')
    if [ "$is_below" -eq 1 ]; then
        ANY_DISK_BELOW_THRESHOLD=true
        log_msg "Disk $D_NAME is below threshold. Free: ${initial_free}GB."
        while true; do
            if [ -f "$STOP_FILE" ]; then log_msg "STOP SIGNAL DETECTED. Stopping gracefully."; break 2; fi
            curr_sim_free=${DISK_SIMULATED_FREE[$D_NAME]}
            is_now_above=$(awk -v cur="$curr_sim_free" -v thold="$THRESHOLD_GB" 'BEGIN { print (cur >= thold) }')
            if [ "$is_now_above" -eq 1 ]; then
                log_msg "Disk $D_NAME is now above threshold (${curr_sim_free}GB). Stopping moves."
                break
            fi
            
            found_move=false
            
            # ========================================================================
            # MANAGED PATH ITERATION
            # ========================================================================
            # Try each managed path in priority order until a valid move is found
            # Format: path:sort_type:excluded_disks
            for entry in "${PATH_ARRAY[@]}"; do
                # Parse the entry into its components
                rel_path="${entry%%:*}"      # The relative path (e.g., "media/movies")
                rest="${entry#*:}"
                sort_type="${rest%%:*}"       # Sorting method (smallest, largest, alphabetical, etc.)
                folder_ex="${rest#*:}"        # Per-path disk exclusions
                
                # Skip this path if the current disk is in its exclusion list
                [[ ",$folder_ex," == *",$disk,"* ]] && continue
                
                # Find the best destination disk for this move
                target=$(find_target_disk "$disk" "$folder_ex")
                [ -z "$target" ] && continue
                
                # Build the full source directory path
                source_dir="$disk/$rel_path"
                [ ! -d "$source_dir" ] && continue
                
                # ====================================================================
                # FOLDER SELECTION LOGIC
                # ====================================================================
                # This section selects the next folder to move based on the sort type.
                # 
                # IMPORTANT BUG FIX: Previously, when a folder was skipped (size 0),
                # the script would continue to the next managed path instead of trying
                # the next folder in the same path. This caused disks to remain under
                # the threshold even when valid folders existed.
                #
                # The fix: We filter out already-processed paths during selection,
                # so the next iteration picks the next valid folder from the same path.
                # ====================================================================
                
                # Build a list of candidate folders with their sort keys
                # Filter out: already processed paths, paths with size 0 (handled later)
                item=$(while IFS= read -r f; do
                    # Skip if already processed in this session
                    [[ "$SIMULATED_PROCESSED_PATHS" == *"$f|"* ]] && continue
                    
                    # Generate sort key based on sort type
                    case "$sort_type" in
                        "smallest"|"largest")
                            # Size-based: get folder size in bytes
                            s=$(du -sb "$f" 2>/dev/null | awk '{print $1}')
                            [ -n "$s" ] && echo "$s|$f"
                            ;;
                        "oldest"|"newest")
                            # Time-based: get modification timestamp
                            t=$(stat -c %Y "$f" 2>/dev/null)
                            [ -n "$t" ] && echo "$t|$f"
                            ;;
                        *)
                            # Alphabetical: use folder name
                            echo "$(basename "$f")|$f"
                            ;;
                    esac
                done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null) | case "$sort_type" in
                    # Sort based on sort type
                    "smallest"|"oldest") sort -n 2>/dev/null ;;      # Numeric ascending
                    "largest"|"newest") sort -rn 2>/dev/null ;;      # Numeric descending
                    "alphabetical_reversed") sort -rf 2>/dev/null ;; # Reverse alphabetical
                    *) sort -f 2>/dev/null ;;                        # Case-insensitive alphabetical
                esac | head -n 1 | cut -d'|' -f2)

                # ====================================================================
                # MOVE EXECUTION
                # ====================================================================
                if [ -n "$item" ]; then
                    size=$(get_folder_size_gb "$item")
                    
                    # ----------------------------------------------------------------
                    # SAFETY CHECK: Skip folders with invalid/zero size
                    # ----------------------------------------------------------------
                    # This prevents infinite loops when:
                    # - Folder is empty (leftover from previous moves)
                    # - Folder is locked/in use by another process
                    # - Permission issues prevent size calculation
                    #
                    # BUG FIX: We do NOT use 'continue' here. Instead, we add the item
                    # to SIMULATED_PROCESSED_PATHS and let the while loop iterate again.
                    # This ensures the next valid folder is selected from the same path.
                    # ----------------------------------------------------------------
                    if [ -z "$size" ] || [ "$size" == "0.0000" ]; then
                        log_msg "WARNING: Unable to determine size of '$item'. File might be in use/locked or empty. Skipping to avoid loop."
                        SIMULATED_PROCESSED_PATHS+="$item|"
                        SKIPPED_PATHS["$item"]=1
                        # Don't continue - let the while loop iterate again to try the next item
                        # This fixes the bug where skipped items prevented further moves on the same disk
                    else
                        # ----------------------------------------------------------------
                        # VALID FOLDER FOUND - Proceed with move
                        # ----------------------------------------------------------------
                        dst="$target/$rel_path/$(basename "$item")"
                        check_path_safety "$item" "$dst"
                        
                        # ----------------------------------------------------------------
                        # DRY RUN MODE: Simulate the move without actually moving files
                        # ----------------------------------------------------------------
                        if [ "$DRY_RUN" == "true" ]; then 
                            log_msg "[DRY RUN] Would move: '$item' ($size GB) to '$dst'"
                            SIMULATED_PROCESSED_PATHS+="$item|"
                            
                            # Update simulated free space counters
                            TOTAL_MOVED_GB=$(awk -v cur="$TOTAL_MOVED_GB" -v sz="$size" 'BEGIN { printf "%.4f", cur + sz }')
                            ((MOVE_COUNT++))
                            DISK_SIMULATED_FREE[$D_NAME]=$(awk -v cur="${DISK_SIMULATED_FREE[$D_NAME]}" -v sz="$size" 'BEGIN { printf "%.4f", cur + sz }')
                            DISK_SIMULATED_FREE[$(basename "$target")]=$(awk -v cur="${DISK_SIMULATED_FREE[$(basename "$target")]}" -v sz="$size" 'BEGIN { printf "%.4f", cur - sz }')
                            key="${D_NAME}->$(basename "$target")"; MOVED_FROM_TO_GB[$key]=$(awk -v cur="${MOVED_FROM_TO_GB[$key]:-0}" -v sz="$size" 'BEGIN { printf "%.4f", cur + sz }')
                            found_move=true; break
                            
                        # ----------------------------------------------------------------
                        # LIVE MODE: Actually move the files
                        # ----------------------------------------------------------------
                        else 
                            log_msg "Moving: '$item' ($size GB) to '$dst'"
                            mkdir -p "$(dirname "$dst")"
                            
                            # Use rsync with --remove-source-files for atomic moves
                            # This preserves attributes and handles partial transfers
                            if rsync -aH --remove-source-files "$item/" "$dst/"; then
                                
                                # Clean up empty subdirectories left by rsync
                                # rsync --remove-source-files only removes files, not directories
                                find "$item" -mindepth 1 -type d -empty -delete 2>/dev/null
                                
                                # Remove the now-empty source folder
                                if [ -z "$(ls -A "$item")" ]; then 
                                    if rm -rf "$item"; then
                                        refresh_user_share "$dst"
                                    else
                                        log_msg "ERROR: Failed to remove empty source folder '$item'."
                                    fi
                                else
                                    log_msg "WARNING: Source folder '$item' not removed. It contains leftover files."
                                fi

                                # Update statistics
                                TOTAL_MOVED_GB=$(awk -v cur="$TOTAL_MOVED_GB" -v sz="$size" 'BEGIN { printf "%.4f", cur + sz }')
                                ((MOVE_COUNT++))
                                DISK_SIMULATED_FREE[$D_NAME]=$(awk -v cur="${DISK_SIMULATED_FREE[$D_NAME]}" -v sz="$size" 'BEGIN { printf "%.4f", cur + sz }')
                                DISK_SIMULATED_FREE[$(basename "$target")]=$(awk -v cur="${DISK_SIMULATED_FREE[$(basename "$target")]}" -v sz="$size" 'BEGIN { printf "%.4f", cur - sz }')
                                key="${D_NAME}->$(basename "$target")"; MOVED_FROM_TO_GB[$key]=$(awk -v cur="${MOVED_FROM_TO_GB[$key]:-0}" -v sz="$size" 'BEGIN { printf "%.4f", cur + sz }')
                                found_move=true; break
                            else
                                # rsync failed - likely file in use or permission issue
                                log_msg "ERROR: Failed to move '$item'. File might be in use/locked. Skipping to avoid loop."
                                SIMULATED_PROCESSED_PATHS+="$item|"
                                SKIPPED_PATHS["$item"]=1
                            fi
                        fi
                    fi
                fi
            done
            
            # If no move was found across all managed paths, exit the while loop
            [ "$found_move" = false ] && break
        done
    fi
done

# ============================================================================
# COMPLETION LOGGING
# ============================================================================
# Log appropriate message based on whether any work was needed
if [ "$ANY_DISK_BELOW_THRESHOLD" = false ]; then
    log_msg "All disks are above the threshold. No files need to be moved."
fi

log_msg "--- Disk Space Management: Execution Finished ---"

# ============================================================================
# NOTIFICATION GENERATION
# ============================================================================
# Send a summary notification to the Unraid WebUI and notification agents
SCRIPT_END_TIME=$(date +"%Y-%m-%d %H:%M:%S")

if [ "$NOTIFY" = "true" ]; then
    # Build the notification body with HTML for UI and plain text for agents
    ui_body="Run finished. Total moved: $(printf "%.2f" "$TOTAL_MOVED_GB")GB in $MOVE_COUNT items.<br><br>";
    [ "$DRY_RUN" == "true" ] && ui_body+="<b>DRY RUN: No files moved.</b><br>";
    ui_body+="Start: $SCRIPT_START_TIME<br>End: $SCRIPT_END_TIME<br><br><b>Disk Summary:</b><br>"
    
    agent_msg="DSM Summary\nTotal: $(printf "%.2f" "$TOTAL_MOVED_GB")GB\n"
    
    # Add per-disk-pair move statistics
    for k in "${!MOVED_FROM_TO_GB[@]}"; do
        src=${k%->*}
        total=${MOVED_FROM_TO_GB[$k]}
        final=${DISK_SIMULATED_FREE[$src]}
        ui_body+=" - $k: $(printf "%.2f" "$total")GB. New free: $(printf "%.2f" "$final")GB.<br>"
        agent_msg+=" - $k: $(printf "%.2f" "$total")GB. New free: $(printf "%.2f" "$final")GB\n"
    done
    
    # Add skipped paths section if any paths were skipped
    if [ "${#SKIPPED_PATHS[@]}" -gt 0 ]; then
        ui_body+="<br><b>Skipped paths (Size 0/Error):</b><br>"
        agent_msg+="\nSkipped paths (Size 0/Error):\n"
        for p in "${!SKIPPED_PATHS[@]}"; do
            ui_body+="$p<br>"
            agent_msg+="$p\n"
        done
    fi

    # Append first 200 lines of log for agent notifications (email, etc.)
    agent_msg+="\n--- Log (First 200 lines) ---\n$(head -n 200 "$TEMP_LOG_FILE")"
    
    # Send notification via Unraid's notify system
    # -e = event type, -s = subject, -d = display message (HTML), -m = full message (plain text)
    /usr/local/emhttp/plugins/dynamix/scripts/notify -e "Disk Space Management" -s "Run Summary" -d "$ui_body" -m "$agent_msg"
fi
