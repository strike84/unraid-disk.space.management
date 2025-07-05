<?php
define('PLUGIN_NAME', 'DiskSpaceManagement');
define('CONFIG_PATH', '/boot/config/plugins/' . PLUGIN_NAME);
define('CONFIG_FILE', CONFIG_PATH . '/settings.cfg');
define('LOG_FILE_PATH_CONFIG_KEY', 'LOG_FILE');

header('Content-Type: text/plain');

$raw_config = file_exists(CONFIG_FILE) ? parse_ini_file(CONFIG_FILE, false, INI_SCANNER_RAW) : [];
$logFile = $raw_config[LOG_FILE_PATH_CONFIG_KEY] ?? '/var/log/diskspacemanagement.log';

if (file_exists($logFile)) {
    echo file_get_contents($logFile);
} else {
    echo "Log file not found at " . htmlspecialchars($logFile) . ". Please run the script at least once to generate it.";
}
?>
