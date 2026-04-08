<?php 
require_once('/usr/local/emhttp/plugins/DiskSpaceManagement/engine.php');
if (!isset($_GET['csrf_token']) || $_GET['csrf_token'] !== $var['csrf_token']) die("Unauthorized");
$config = parse_ini_file(CONFIG_FILE, false, INI_SCANNER_RAW); 
$logFile = !empty($config['LOG_FILE']) ? $config['LOG_FILE'] : '/var/log/diskspacemanagement.log'; 
if (isset($_GET['clear'])) { file_put_contents($logFile, ""); exit; } 
header('Content-Type: text/plain'); 
echo file_exists($logFile) ? file_get_contents($logFile) : "Log file not found."; 
?>
