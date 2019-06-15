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