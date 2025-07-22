<?php
// Define constants
define('PLUGIN_NAME', 'DiskSpaceManagement');
define('PLUGIN_VERSION', '2025.07.22');
define('CONFIG_PATH', '/boot/config/plugins/' . PLUGIN_NAME);
define('CONFIG_FILE', CONFIG_PATH . '/settings.cfg');

// Variable to hold a success message after saving
$update_message = "";

// Function to read a setting value and escape it for safe HTML output
function get_config_val($key, $default = '') {
    if (!file_exists(CONFIG_FILE)) {
        return htmlspecialchars($default, ENT_QUOTES, 'UTF-8');
    }
    $config = parse_ini_file(CONFIG_FILE, false, INI_SCANNER_RAW);
    $value = $config[$key] ?? $default;
    return htmlspecialchars($value, ENT_QUOTES, 'UTF-8');
}

// Handle POST request to save settings.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['save_settings'])) {
    if (!is_dir(CONFIG_PATH)) {
        mkdir(CONFIG_PATH, 0770, true);
    }
    
    // Load the old settings for comparison
    $old_config = file_exists(CONFIG_FILE) ? parse_ini_file(CONFIG_FILE, false, INI_SCANNER_RAW) : [];
    
    $new_config = $_POST;
    unset($new_config['save_settings']);

    // Determine what changed
    $cron_changed = ($old_config['CRON_SCHEDULE'] ?? null) !== ($new_config['CRON_SCHEDULE'] ?? null);
    
    $old_other_settings = $old_config;
    if (isset($old_other_settings['CRON_SCHEDULE'])) unset($old_other_settings['CRON_SCHEDULE']);
    $new_other_settings = $new_config;
    if (isset($new_other_settings['CRON_SCHEDULE'])) unset($new_other_settings['CRON_SCHEDULE']);
    $other_settings_changed = $old_other_settings !== $new_other_settings;

    // Save the new settings
    $cfg_content = "";
    foreach($new_config as $key => $value) {
        $escaped_value = str_replace('"', '\"', $value);
        $cfg_content .= $key . '="' . $escaped_value . '"' . PHP_EOL;
    }
    file_put_contents(CONFIG_FILE, $cfg_content);

    // Update cron if its schedule changed
    if ($cron_changed) {
        $cron_schedule = $new_config['CRON_SCHEDULE'] ?? '0 3 * * *';
        $log_file = $new_config['LOG_FILE'] ?? '/var/log/diskspacemanagement.log';
        $script_path = "/usr/local/emhttp/plugins/" . PLUGIN_NAME . "/scripts/disk_space_management.sh";
        $command = "/bin/bash " . escapeshellarg($script_path);
        
        $cron_file_path = "/boot/config/plugins/dynamix/" . PLUGIN_NAME . ".cron";
        
        $wrong_cron_path = CONFIG_PATH . "/" . PLUGIN_NAME . ".cron";
        if (file_exists($wrong_cron_path)) {
            unlink($wrong_cron_path);
        }

        if (strtolower($cron_schedule) === 'disabled') {
            if (file_exists($cron_file_path)) {
                unlink($cron_file_path);
            }
        } else {
            // The script now handles its own logging, so we don't need redirection here.
            $cron_content = "# Auto-generated cron job for DiskSpaceManagement" . PHP_EOL;
            $cron_content .= "$cron_schedule $command" . PHP_EOL;
            file_put_contents($cron_file_path, $cron_content);
        }
        
        exec("update_cron");
    }

    // Set the appropriate success message
    if ($cron_changed && $other_settings_changed) {
        $update_message = "Settings saved, cron schedule successfully updated.";
    } elseif ($cron_changed) {
        $update_message = "Cron schedule successfully updated.";
    } elseif ($other_settings_changed) {
        $update_message = "Settings saved.";
    } else {
        $update_message = "No changes were made.";
    }
}
?>
<style>
    .log-container { background-color: #2b2b2b; color: #f1f1f1; font-family: monospace; white-space: pre-wrap; word-wrap: break-word; padding: 15px; border-radius: 5px; height: 500px; overflow-y: scroll; border: 1px solid #444; }
    .success-message { padding: 10px; background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; border-radius: 5px; margin-bottom: 15px; }
</style>
<div id="diskspacemanagement">
    <div style="display:flex; justify-content:space-between; align-items:center;">
        <div>
            <h2>Disk Space Management <span style="font-size: 0.8em; color: #999;"><?= PLUGIN_VERSION ?></span></h2>
            <p>Automated disk space management for your media library.</p>
        </div>
    </div>
    
    <?php if (!empty($update_message)): ?>
        <div class="success-message">
            <?= htmlspecialchars($update_message) ?>
        </div>
    <?php endif; ?>

    <div class="tabs">
        <button class="tab-button active" onclick="showTab('settings')">Settings</button>
        <button class="tab-button" onclick="showTab('logs')">Logs</button>
        <button class="tab-button" onclick="showTab('about')">About</button>
    </div>

    <div id="tab-settings" class="tab-content" style="display: block;">
        <form id="diskspacemanagement_form" method="post" action="">
            <input type="hidden" name="save_settings" value="true">
            <dl>
                <dt>Free Space Threshold (GB)</dt>
                <dd><input type="number" name="THRESHOLD_GB" value="<?= get_config_val('THRESHOLD_GB', '100') ?>" size="5"></dd>
                <blockquote class="inline_help"><p>The script will start moving files from any disk with free space below this value.</p></blockquote>
                
                <dt>Dry Run</dt>
                <dd>
                  <select name="DRY_RUN">
                    <option value="true" <?= get_config_val('DRY_RUN', 'true') == 'true' ? 'selected' : '' ?>>Enabled</option>
                    <option value="false" <?= get_config_val('DRY_RUN', 'true') == 'false' ? 'selected' : '' ?>>Disabled</option>
                  </select>
                </dd>
                <blockquote class="inline_help"><p>When enabled, the script will log what it would do without actually moving any files. Recommended for testing.</p></blockquote>

                <dt>Send Notifications</dt>
                <dd>
                  <select name="NOTIFY">
                    <option value="true" <?= get_config_val('NOTIFY', 'true') == 'true' ? 'selected' : '' ?>>Yes</option>
                    <option value="false" <?= get_config_val('NOTIFY', 'true') == 'false' ? 'selected' : '' ?>>No</option>
                  </select>
                </dd>
                <blockquote class="inline_help"><p>Send a notification to the Unraid UI when the script starts and finishes.</p></blockquote>

                <dt>Log File Path</dt>
                <dd><input type="text" name="LOG_FILE" value="<?= get_config_val('LOG_FILE', '/var/log/diskspacemanagement.log') ?>" size="60"></dd>
                <blockquote class="inline_help"><p>Path to store the script execution log. If you want persistent logs store it on the cache drive or flash drive.</p></blockquote>

                <dt>Movie Library Paths</dt>
                <dd><input type="text" name="MOVIE_DIRS" value="<?= get_config_val('MOVIE_DIRS', 'media/Movies') ?>" size="60"></dd>
                <blockquote class="inline_help"><p>Comma-separated list of paths, relative to the disk root (e.g., media/Movies,media/4K_Movies).</p></blockquote>

                <dt>TV Show Library Paths</dt>
                <dd><input type="text" name="TV_SHOW_DIRS" value="<?= get_config_val('TV_SHOW_DIRS', 'media/TV') ?>" size="60"></dd>
                <blockquote class="inline_help"><p>Comma-separated list of paths, relative to the disk root (e.g., media/TV Shows,media/Kid Shows</p></blockquote>
                
                <dt>Excluded Disks</dt>
                <dd><input type="text" name="EXCLUDED_DISKS" value="<?= get_config_val('EXCLUDED_DISKS', '') ?>" size="60"></dd>
                <blockquote class="inline_help"><p>Comma-separated list of full disk paths to exclude from all operations (e.g. /mnt/disk1,/mnt/disk2).</p></blockquote>

                <dt>Cron Schedule</dt>
                <dd>
                <input type="text" name="CRON_SCHEDULE" value="<?= get_config_val('CRON_SCHEDULE', '0 3 * * *') ?>" size="60"></dd>
                <blockquote class="inline_help"><p>Standard cron format for automatic execution. Enter "disabled" to turn off. Example: '0 3 * * *' runs at 3:00 AM every day. See this link if you need help figuering out what to put here: https://crontab.guru/#0_3_*_*_* It's recommended to set the cron schedule to a time when you know the mover has finished.</p></blockquote>
                </dd>
            </dl>
            <div id="buttons" style="margin-top: 20px;">
              <input type="button" value="Run Script Now" onclick="runScript()">
              <input type="submit" value="Apply">
            </div>
        </form>
    </div>
    <div id="tab-logs" class="tab-content" style="display: none;">
        <h3>Script Log</h3>
        <p>This log shows the output from the log file specified in the settings. It will auto-refresh every 10 seconds while this tab is active.</p>
        <div id="log-content" class="log-container">Loading log...</div>
    </div>
    <div id="tab-about" class="tab-content" style="display: none;">
        <h3>About Disk Space Management</h3>
        <p>For more information about each setting click the help button in the top right corner of the UnRaid web ui. This plugin was created mainly for those who use the split-level feature in Unraid. Due to how split level works, it will ignore the minimum free space setting and continue to move stuff to disks that are full/almost full. This is because split level tries to keep files and folders that belong together based on your split level setting on the same disk, and split level trumps all other settings. Even if there's little space left on the disk. So to combat this, this plugin will automatically move Movies and TV shows from disks that are below the threshold setting to the disk with the most free space available. It prioritizes to move movies first, then if no movies are found it will go to TV shows and move the shows with the fewest seasons first. It's recommended to set the cron schedule to a time when you know the mover has finished.</p>
        <p><strong>Version:</strong> <?= PLUGIN_VERSION ?></p>
    </div>
</div>
<div id="progress_iframe_container" style="display:none; margin-top:20px;">
    <h3>Script Output</h3>
    <iframe name="progress_iframe" style="width:100%; height: 500px; border: 1px solid #ccc; border-radius: 5px; background-color: #2b2b2b;"></iframe>
</div>
<script>
function showTab(tabName){$('.tab-content').hide();$('#tab-'+tabName).show();$('.tab-button').removeClass('active');$('button[onclick="showTab(\''+tabName+'\')"]').addClass('active');if(tabName==='logs'){updateLog();}}
function runScript(){$('#progress_iframe_container').show();$('iframe[name="progress_iframe"]').attr('src','/plugins/<?=PLUGIN_NAME?>/run_handler.php');}
function updateLog(){$.get('/plugins/<?=PLUGIN_NAME?>/log_handler.php',function(data){$('#log-content').text(data).scrollTop($('#log-content')[0].scrollHeight);});}
setInterval(function(){if($('#tab-logs').is(':visible')){updateLog();}},10000);
$(document).ready(function(){showTab('settings');});
</script>
