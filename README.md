# unraid-disk.space.management
Unraid disk space management plugin

Description:
This plugin automates disk space management on an Unraid server. It monitors
disks, moves media files from full disks to those with more space, and
ensures media is organized correctly. Primarily for those who use split-level.

Features:
- Intelligent Threshold Monitoring: Continuously monitors array disks and triggers move operations when free space falls below your defined GB threshold.
- Folder Priority Queue: Features a drag-and-drop interface that allows you to prioritize which directories are processed first.
- Per-Path Granular Sorting: You can independently configure sorting rules for every folder in your queue, including Smallest First, Alphabetical (A-Z or Z-A), Newest First, or Oldest First.
- Dual-Layer Disk Exclusions: Provides both global disk exclusions and folder-specific exclusions to give you precise control over where data can and cannot be moved.
- Interactive Path Picker: Includes a built-in visual folder browser to easily select and add new management paths directly from your Unraid array.
- Real-Time Status Tracking: A live dashboard badge displays whether the engine is currently "IDLE" or "RUNNING".
- Advanced Safety Guards: Integrated protection prevents accidental moves to or from /mnt/user and includes loop prevention logic for simulated runs.
- Smart DRY RUN Mode: Safely test your configuration with a full simulation that logs exactly what would happen without moving a single file.
- High-Performance File Transfer: Uses rsync to move data, ensuring all permissions, attributes, and hard links are perfectly preserved.
- Modernized Log Terminal: Features a dedicated log management tab with a high-visibility console, auto-scrolling, and the ability to clear logs directly from the UI.
- Automated Scheduling: Fully customizable cron scheduling to ensure management tasks run at the most convenient times for your server.
