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
                   the first time. Your myNode may run slowly during this period.";
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

function toggleEnabled(short_name, full_name, enable) {
    //enabled = application_data[short_name]["is_enabled"];
    //full_name = application_data[short_name]["name"];
    
    if ( !enable ) {
        // Disabling
        openConfirmDialog("confirm-dialog", 
                          "Disable "+full_name, 
                          "Are you sure you want to disable "+full_name+"?",
                           function(){
                                $( this ).dialog( "close" );
                                $('#loading_spinner_overlay').fadeIn();
                                window.location.href="/toggle-enabled?app="+short_name
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
                                window.location.href="/toggle-enabled?app="+short_name
                           });
    }
}