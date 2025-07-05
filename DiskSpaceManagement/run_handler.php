<?php
header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html>
<head>
    <style>
        body {
            background-color: #2b2b2b;
            color: #f1f1f1;
            font-family: monospace;
            margin: 10px;
            white-space: pre;
        }
    </style>
</head>
<body>
<?php
echo "Starting Disk Space Management script...\n\n";
flush();
ob_flush();

$script_path = "/usr/local/emhttp/plugins/DiskSpaceManagement/scripts/disk_space_management.sh";

passthru("/bin/bash " . escapeshellarg($script_path));

echo "\n\nScript finished.";
?>
</body>
</html>
