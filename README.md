# unraid-disk.space.management
Unraid disk space management plugin

Description:
This script automates disk space management on an Unraid server. It monitors
disks, moves media files from full disks to those with more space, and
ensures media is organized correctly. Primarily for those how use split level.

Features:
- Monitors disks based on a defined free space threshold.
- Moves movies and TV shows to maintain free space.
- Prioritizes moving Movies then smaller TV shows first to be more efficient.
- Supports multiple media directory locations.
- Allows for specific disks to be excluded from operations.
- Uses rsync to preserve permissions, attributes, and hard links.
- Includes a smart DRY RUN mode for safe, accurate testing.
- Robust logging for all actions.

