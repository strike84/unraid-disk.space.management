<?php 
require_once('/usr/local/emhttp/plugins/DiskSpaceManagement/engine.php');
if (!isset($_GET['csrf_token']) || $_GET['csrf_token'] !== $var['csrf_token']) die("Unauthorized");
touch('/tmp/dsm.stop'); 
?>
