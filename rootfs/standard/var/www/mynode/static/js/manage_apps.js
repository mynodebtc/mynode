//
// These functions are used both by the manage_apps page and individual app pages
//

// ==========================================
// Manage running apps
// ==========================================
function restart(name, short_name) {
    if ( confirm("Are you sure you want to restart "+name+"?\n\nRestarting services like Bitcoin or LND may have side effects. If so, restart the device.") ) {
        $('#loading_spinner_message').html("Restarting...");
        $('#loading_spinner_overlay').fadeIn();
        window.location.href='/apps/restart-app?app='+short_name;
    }
}

function restart_app_via_api(name, short_name) {
    if ( confirm("Are you sure you want to restart "+name+"?") ) {
        $('#loading_spinner_message').html("Restarting...");
        $('#loading_spinner_overlay').fadeIn();
        $.get('/api/restart_app?app='+short_name)
            .done(function( data ) {
                if (data != "OK") {
                    alert("Error restarting app: "+data)
                }
                $('#loading_spinner_overlay').fadeOut();
            }
        );
    }
}

// ==========================================
// Manage app installations
// ==========================================
function upgrade(name, short_name) {
    if ( confirm("Are you sure you want to upgrade "+name+"? This will reboot your device.") ) {
        $('#loading_spinner_message').html("Upgrading...");
        $('#loading_spinner_overlay').fadeIn();
        window.location.href='/settings/reinstall-app?app='+short_name;
    }
}

function reinstall(name, short_name) {
    if ( confirm("Are you sure you want to re-install "+name+"? This will reboot your device.") ) {
        $('#loading_spinner_message').html("Re-installing...");
        $('#loading_spinner_overlay').fadeIn();
        window.location.href='/settings/reinstall-app?app='+short_name;
    }
}

function install(name, short_name) {
    if ( confirm("Are you sure you want to install "+name+"? This will reboot your device.") ) {
        $('#loading_spinner_message').html("Installing...");
        $('#loading_spinner_overlay').fadeIn();
        window.location.href='/settings/reinstall-app?app='+short_name;
    }
}

function uninstall(name, short_name, return_page="") {
    if ( confirm("Are you sure you want to uninstall "+name+"? ") ) {
        $('#loading_spinner_message').html("Uninstalling...");
        $('#loading_spinner_overlay').fadeIn();
        r = ""
        if (return_page != "") {
            r = "&return_page="+return_page
        }
        window.location.href='/settings/uninstall-app?app='+short_name+r;
    }
}

function remove_from_device(name, short_name) {
    if ( confirm("Are you sure you want to uninstall "+name+"? ") ) {
        $('#loading_spinner_message').html("Removing...");
        $('#loading_spinner_overlay').fadeIn();
        window.location.href='/settings/remove-app?app='+short_name;
    }
}

// ==========================================
// Toggle enable/disable functions
// ==========================================
function get_custom_enable_message(short_name) {
    message = "";
    if (short_name == "electrs") {
        message = "Enabling Electrum Server will take several days to fully sync for \
                   the first time. Your MyNode may run slowly during this period.";
    } else if (short_name == "vpn") {
        message = "Enabling VPN will set your IP to a static IP rather than a dynamic one via DHCP. \
                   The initial setup may take about an hour.";
    } else if (short_name == "dojo") {
        message = "Enabling Dojo for the first time will reboot your device and install Dojo.";
    }
    if (message != "") {
        message += "<br/><br/>";
    }
    return message;
}

function toggleEnabled(short_name, full_name, enable, return_page="") {
    //enabled = application_data[short_name]["is_enabled"];
    //full_name = application_data[short_name]["name"];

    r = ""
    if (return_page != "") {
        r = "&return_page="+return_page
    }
    
    if ( !enable ) {
        // Disabling
        openConfirmDialog("confirm-dialog", 
                          "Disable "+full_name, 
                          "Are you sure you want to disable "+full_name+"?",
                           function(){
                                $( this ).dialog( "close" );
                                $('#loading_spinner_overlay').fadeIn();
                                window.location.href="/toggle-enabled?app="+short_name+r
                           });
    } else {
        custom_message = "";
        // Enabling
        openConfirmDialog("confirm-dialog", 
                          "Enable "+full_name, 
                          get_custom_enable_message(short_name) +
                          "Are you sure you want to enable "+full_name+"?",
                           function(){
                                $( this ).dialog( "close" );
                                $('#loading_spinner_overlay').fadeIn();
                                window.location.href="/toggle-enabled?app="+short_name+r
                           });
    }
}

// ==========================================
// Manage app storage (data_folder)
// ==========================================

function backup_data_folder_via_api(name, short_name) {
    if ( confirm("Are you sure you want to backup "+name+"? This will stop, backup data and start app.") ) {
        $('#loading_spinner_message').html("Making backup...");
        $('#loading_spinner_overlay').fadeIn();
        $.get('/api/backup_app_data?app='+short_name)
            .done(function( data ) {
                if (data != "OK") {
                    alert("Error backupping app data: "+data)
                }
                $('#loading_spinner_overlay').fadeOut();
            }
        );
    }
}

function restore_data_folder_via_api(name, short_name) {
    if ( confirm("Are you sure you want to restore "+name+"? This will stop, DELETE DATA, restore backup and start app.") ) {
        $('#loading_spinner_message').html("Restoring...");
        $('#loading_spinner_overlay').fadeIn();
        $.get('/api/restore_app_data?app='+short_name)
            .done(function( data ) {
                if (data != "OK") {
                    alert("Error restoring app data: "+data)
                }
                $('#loading_spinner_overlay').fadeOut();
            }
        );
    }
}

function reset_data_folder_via_api(name, short_name) {
    if ( confirm("Are you sure you want to reset "+name+"? This will stop app, RESET ALL THE APP DATA and start app.") ) {
        $('#loading_spinner_message').html("Reseting app...");
        $('#loading_spinner_overlay').fadeIn();
        $.get('/api/remove_app_data?app='+short_name)
            .done(function( data ) {
                if (data != "OK") {
                    alert("Error removing app data: "+data)
                }
                $('#loading_spinner_overlay').fadeOut();
            }
        );
    }
}