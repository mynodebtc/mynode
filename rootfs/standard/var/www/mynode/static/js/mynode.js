// Refresh page after N seconds
function refreshIn(seconds) {
    setTimeout(function() {
        //window.location.reload();
        alert("reload")
    }, seconds*1000); 
}

// Open info dialog
function openInfoDialog(divid, title, message) {
    $("#"+divid).html("<p>"+message+"</p>")
    info_dialog = $("#"+divid).dialog({
        title: title,
        resizable: false,
        height: "auto",
        width: 600,
        modal: true,
        position: { my: "center top", at: "center top", of: window, collision: "none" },
        buttons: {
            "OK": function() {
                $( this ).dialog( "close" );
            }
        }
    });
    info_dialog.dialog("open");
}

// Open confirm dialog
function openConfirmDialog(divid, title, message, okFunction) {
    $("#"+divid).html("<p>"+message+"</p>")
    confirm_dialog = $( "#"+divid ).dialog({
        title: title,
        resizable: false,
        height: "auto",
        width: 600,
        modal: true,
        position: { my: "center top", at: "center top", of: window, collision: "none" },
        buttons: {
            "OK": okFunction,
            Cancel: function() {
                $( this ).dialog( "close" );
            }
        }
    });
}

// Show alert popup with contents
function showAlertPopup(divid, message) {
    $("#"+divid).html(message);
    $("#"+divid).show().delay(3000).fadeOut();
}

// Check if using tor
function is_using_tor() {
    if (location.hostname.includes(".onion")) {
        return true;
    }
    return false;
}

// Open new tab
function open_new_mynode_tab(port, protocol="same") {
    hostname=location.hostname
    if (protocol == "same") {
        protocol = location.protocol
    } else if (protocol == "http" || protocol == "https") {
        protocol = protocol + ":"
    }
    url = protocol+'//'+hostname+':'+port
    window.open(url,'_blank');
}

// Open app in new tab
function open_app_in_new_tab(http_port, https_port="NA", requires_https=false, custom_tor_address="NA", tor_http_port="80", tor_https_port="443") {
    protocol=location.protocol
    hostname=location.hostname
    port_string=""

    if (is_using_tor() && custom_tor_address != "NA") {
        hostname=custom_tor_address
        // Use "default" port - either 80 or 443 for HTTP/HTTPS unless overriden
        if (protocol == "http:" && tor_http_port != "80") {
            port_string=":"+tor_http_port
        }
        if (protocol == "https:" && tor_https_port != "443") {
            port_string=":"+tor_https_port
        }

        // If app is HTTP only
        if (tor_https_port == "NA") {
            protocol = "http:"
            port_string = ":"+tor_http_port
        }
    } else {
        if (protocol == "http:" && http_port != "80") {
            port_string=":"+http_port
        }
        if (protocol == "https:" && https_port != "443") {
            port_string=":"+https_port
        }

        // If app is HTTP only
        if (https_port == "NA") {
            protocol = "http:"
            port_string = ":"+http_port
        }
    }
    
    url = protocol+'//'+hostname+port_string
    window.open(url,'_blank');
}