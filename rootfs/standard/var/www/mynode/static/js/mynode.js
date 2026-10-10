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

// Ask for the admin password, then POST it with the given fields to action
function openPasswordDialog(title, message, action, fields={}, onSubmit=null) {
    var form = $("<form>", {method: "POST", action: action});
    form.append($("<p>").text(message));
    form.append($("<b>").text("Password:"), $("<br>"));
    form.append($("<input>", {type: "password", name: "password", "class": "text ui-widget-content ui-corner-all"}));
    $.each(fields, function(name, value) {
        form.append($("<input>", {type: "hidden", name: name, value: value}));
    });
    // Allow form submission with keyboard without duplicating the dialog button
    form.append($("<input>", {type: "submit", tabindex: -1, style: "position:absolute; top:-1000px"}));
    form.on("submit", function() {
        if (onSubmit) {
            onSubmit();
        }
    });
    $("<div>").append(form).appendTo("body").dialog({
        title: title,
        resizable: false,
        height: "auto",
        width: 600,
        modal: true,
        position: { my: "center top", at: "center top", of: window, collision: "none" },
        buttons: {
            "OK": function() {
                form.trigger("submit");
            },
            Cancel: function() {
                $( this ).dialog( "close" );
            }
        },
        close: function() {
            $( this ).dialog( "destroy" ).remove();
        }
    });
}

// Ask for the admin password, then POST it with the given fields to url and pass the returned
// value to onValue. The value is never in the page until then.
function openRevealDialog(url, fields, onValue) {
    var form = $("<form>");
    var password = $("<input>", {type: "password", "class": "text ui-widget-content ui-corner-all"});
    var error = $("<p>", {"class": "red_text"}).hide();
    form.append($("<p>").text("Please enter your password to show this."));
    form.append($("<b>").text("Password:"), $("<br>"), password, error);
    // Allow form submission with keyboard without duplicating the dialog button
    form.append($("<input>", {type: "submit", tabindex: -1, style: "position:absolute; top:-1000px"}));
    var dialog = $("<div>").append(form).appendTo("body").dialog({
        title: "Enter Password",
        resizable: false,
        height: "auto",
        width: 600,
        modal: true,
        position: { my: "center top", at: "center top", of: window, collision: "none" },
        buttons: {
            "Show": function() {
                form.trigger("submit");
            },
            Cancel: function() {
                $( this ).dialog( "close" );
            }
        },
        close: function() {
            $( this ).dialog( "destroy" ).remove();
        }
    });
    form.on("submit", function(event) {
        event.preventDefault();
        $.post(url, $.extend({password: password.val()}, fields))
            .done(function(data) {
                if (data["value"] == null) {
                    error.text(data["error"] || "Error").show();
                    password.val("");
                    return;
                }
                dialog.dialog( "close" );
                onValue(data["value"]);
            })
            .fail(function() {
                error.text("Request failed").show();
            });
    });
}

// A secret shown on request: <span class="reveal_secret" data-secret="..." [data-app="..."] [data-url="..."]>
// holding a .reveal_secret_button and a hidden .reveal_secret_value with .reveal_secret_text and
// an optional .reveal_secret_copy icon
$(document).on("click", ".reveal_secret_button", function() {
    var container = $(this).closest(".reveal_secret");
    var fields = {};
    if (container.attr("data-secret")) {
        fields["secret"] = container.attr("data-secret");
    }
    if (container.attr("data-app")) {
        fields["app"] = container.attr("data-app");
    }
    openRevealDialog(container.attr("data-url") || "/api/reveal_secret", fields, function(value) {
        container.find(".reveal_secret_text").text(value);
        container.find(".reveal_secret_button").hide();
        container.find(".reveal_secret_copy").toggle(!!(navigator.clipboard && window.isSecureContext));
        container.find(".reveal_secret_value").show();
    });
});
$(document).on("click", ".reveal_secret_copy", function() {
    var icon = $(this);
    var text = icon.closest(".reveal_secret").find(".reveal_secret_text").text();
    function showResult(message) {
        if ($("#alert_popup").length) {
            showAlertPopup("alert_popup", $("<b>").text(message));
        } else {
            icon.attr("title", message);
        }
    }
    navigator.clipboard.writeText(text).then(function() {
        showResult("Copied!");
    }, function() {
        showResult("Copy failed!");
    });
});

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
        if (tor_https_port == "NA" || tor_https_port == "None") {
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
        if (https_port == "NA" || https_port == "None") {
            protocol = "http:"
            port_string = ":"+http_port
        }

        // If app is HTTPS only
        if (http_port == "NA" || http_port == "None") {
            protocol = "https:"
            port_string = ":"+https_port
        }
    }

    url = protocol+'//'+hostname+port_string
    window.open(url,'_blank');
}