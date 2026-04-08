<?php 
require_once('/usr/local/emhttp/plugins/DiskSpaceManagement/engine.php');
if (!isset($_GET['csrf_token']) || $_GET['csrf_token'] !== $var['csrf_token']) die("Unauthorized");
exec("/bin/bash /usr/local/emhttp/plugins/DiskSpaceManagement/scripts/disk_space_management.sh > /dev/null 2>&1 &"); 
?>
