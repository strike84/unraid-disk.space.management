# Changelog
## 2026.04.08
- Script/UI: Fixed an issue on Unraid 7.3.0 beta where saving settings failed with an "AJAX Save Failed" (HTTP 500 or 403 Forbidden) error due to PHP 8.4 changes to `parse_ini_file` and changes to session-based CSRF tokens.
- UI: Fixed a secondary issue where Unraid's PageRenderer prepended HTML to the AJAX response, preventing the success confirmation from displaying.

## 2026.02.20
- Feature/script/UI: Added support for largest files first sorting order
- Script: Fixed empty folders issue were the continue statement skipped to the next managed path in the for entry loop.

## 2026.01.17
- Script/UI: Changed the cron setting to have a dropdown to enable/disable, and saving the schedule so it isn't lost if disabled.

## 2026.01.09
- Script: Logs and skips files that are in use/locked or returns a 0 in size which causes the Infinite loop.
- Fixed display issues triggering the "mobile" view on laptops and unraid version before 7.2.

## 2026.01.07
- Feature: Added "Stop Script" button to Logs tab for graceful termination.
- Script: Fixed "Broken pipe" and "sort: write error" in logs.
- UI: Fixed dropdown rendering issues in Azure and Grey themes.

## 2025.12.31-3
- Engine: Replaced 'bc' dependency with 'awk' for better compatibility across Unraid versions.

## 2025.12.31
🚀 Major Engine & Logic Overhaul
- Unified Path Management: Replaced the rigid "Movie/TV/Other" category system with a flexible Folder Priority Queue.
- Drag-and-Drop Prioritization: Added a new interactive UI that allows you to drag paths to set their processing priority (top-to-bottom).
- Per-Path Granular Controls:
- Disk Exclusions: You can now exclude specific disks for individual folders, independent of global exclusion settings.
- Independent Sorting: Each folder in the queue can have its own unique sorting method (e.g., sort Movies by size, but TV Shows alphabetically).
- Dynamic Path Migration: Integrated an automatic migration script that converts your legacy "Movie/TV/Other" settings into the new Queue format upon first run.
- Interactive Path Picker: Introduced a visual folder browser (Picker) to select paths directly from your Unraid array instead of typing them manually.
- Live Status Monitoring: Added a real-time status badge in the header to show if the management engine is currently IDLE or RUNNING.

🔧 Bug Fixes & Safety
- Cron System: Fixed critical issue where Cron schedules were not being written to the system's cron directory.
- FUSE Loop Prevention: Integrated a safety guard to prevent the script from getting stuck in loops during Dry Runs by tracking simulated processed paths.
- Critical Safety Guard: Added an explicit check to block /mnt/user from being used as a source or destination, preventing potential data loss from "User Share to Disk" move errors.
- Fixed bugs and updated code to comply with unRAIDS security guidelines for plugins.


🎨 UI & UX Enhancements
- Modernized Interface: Completely redesigned the settings page with a dark-themed, grid-based layout using the "Inter" font.
- Tabbed Navigation: Separated Settings, Logs, Changelog, and About info into clean, easy-to-navigate tabs.
- Enhanced Logging: The log terminal now features a high-contrast "Matrix" style (green on black) with auto-scrolling in Live mode. A refresh button for Dry Run to making it easier to read logs during a Dry Run and a one-click Clear Log function.

## 2025.11.08
- Script: An attempt to fix the "user share caching issue", where the FUSE user share system is not updated to reflect the files new location. This fix will now automatically trigger a "cache refresh" after each successful file move, ensuring the file is immediately visible in the user share.

## 2025-09-19
- Script: Changed the script to use base-10 units so the space reproted matches the webui more correctly.
- Script: Fixed calculation of effective space.

## 2025.09.01-3
- Script: Fixed alphabetical sorting to be case-insensitive (e.g., 'A' and 'a' are treated equally).

## 2025.09.01-2
- Script: Fixed a bug where the `sort` command would fail due to incorrect argument quoting.

## 2025.09.01
- Feature: Added a third "Other" library category for managing any type of folder.
- Feature: Implemented configurable move priority. Users can now define the order in which libraries are processed (e.g., tv,movies,other).
- Feature: Added advanced, per-library sorting options. Each library type (Movies, TV, Other) can be sorted independently by:
    - Smallest/Newest/Oldest First
    - Alphabetical (A-Z or Z-A)
    - Random
- Feature: Retained "Fewest Seasons" as a sorting option unique to TV shows.
- Script: Major refactor of the item collection logic to support the new dynamic priority and sorting systems.

## 2025.08.26-2
- Script: Reverted to using whole numbers to calculate free space.
- Script: Fixed log now showing in the iframe. 

## 2025.08.26
- Script: Implemented a new temporary logging system. The log snippet sent in notifications is now guaranteed to be from the current run only. The session log is then appended to the main log file.
- Script: Finalized notification logic. Email/Agent messages are now correctly formatted with plain text and include a log snippet. UI notifications use HTML for rich formatting.
- Script: Corrected the folder size calculation logic.

## 2025.08.23
- UI: Corrected the alignment of help text blocks on the settings page.

## 2025.08.22
- UI: Added compatibility fixes for Unraid 7.2.0 responsive web GUI.
- UI: Corrected spacing for tab and action buttons.
- UI: Corrected width of the 'Excluded Disks' dropdown container and trigger for visual consistency.

## 2025.08.02
- Feature/UI: Added a more user-friendly way to exclude disks by adding checkboxes that the user can click to exclude the disk they want.

## 2025.07.27
- Feature: Added validation for Movie and TV Show library paths.
- UI: An error message is now displayed on the settings page if a path is invalid (case-sensitive).
- UI: Added changelog button which displays changes.
- Script: The script now logs a warning and skips invalid paths instead of attempting to use them.

## 2025.07.22
- Fixed creation of logfile when the script is run manually
