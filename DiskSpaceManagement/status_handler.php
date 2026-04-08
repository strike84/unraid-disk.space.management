<?php 
require_once('/usr/local/emhttp/plugins/DiskSpaceManagement/engine.php');
if (!isset($_GET['csrf_token']) || $_GET['csrf_token'] !== $var['csrf_token']) die("Unauthorized");
header('Content-Type: text/plain'); echo file_exists('/tmp/dsm.running') ? "running" : "idle"; 
?>
