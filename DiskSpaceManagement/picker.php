<?php 
require_once('/usr/local/emhttp/plugins/DiskSpaceManagement/engine.php');
if (!isset($_GET['csrf_token']) || $_GET['csrf_token'] !== $var['csrf_token']) die("Unauthorized");
$path = $_GET['path'] ?? '/mnt/user'; 
if ((strpos($path, '/mnt/user') !== 0 && strpos($path, '/mnt/user0') !== 0) || strpos($path, '..') !== false) die(json_encode([])); 
$dirs = []; 
if (is_dir($path)) { foreach (scandir($path) as $file) { if ($file == '.' || $file == '..') continue; if (is_dir("$path/$file")) $dirs[] = ['name' => $file, 'path' => "$path/$file"]; } } 
header('Content-Type: application/json'); echo json_encode($dirs); ?>
