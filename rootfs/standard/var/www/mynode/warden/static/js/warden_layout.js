$(document).ready(function () {
    console.log("-------------");
    console.log("00000080   01 04 45 54 68 65 20 54  69 6D 65 73 20 30 33 2F   ..EThe Times 03/");
    console.log("00000090   4A 61 6E 2F 32 30 30 39  20 43 68 61 6E 63 65 6C   Jan/2009 Chancel");
    console.log("000000A0   6C 6F 72 20 6F 6E 20 62  72 69 6E 6B 20 6F 66 20   lor on brink of ");
    console.log("000000B0   73 65 63 6F 6E 64 20 62  61 69 6C 6F 75 74 20 66   second bailout f");
    console.log("000000C0   6F 72 20 62 61 6E 6B 73  FF FF FF FF 01 00 F2 05   or banksÿÿÿÿ..ò.");
    console.log("--------------");

    // Tests and Price
    test_tor();
    BTC_price();
    get_version();


    // Updates BTC Price every 30 seconds
    window.setInterval(function () {
        BTC_price();
        check_activity();
        get_version();
    }, 30000);

    $(function () {
        $('[data-toggle="tooltip"]').tooltip()
    })

    $('#myModal').on('shown.bs.modal', function () {
        $('#myInput').trigger('focus')

    })


    $('#exampleModal').on('show.bs.modal', function () {
        $(this).find('.modal-body').css({
            width: 'auto', //probably not needed
            height: 'auto', //probably not needed
            'max-height': '100%'
        });
    });

    $("#menu-toggle").click(function (e) {
        e.preventDefault();
        $("#wrapper").toggleClass("toggled");
        $("#btn_tgl").toggleClass("down");
    });

});


function BTC_price() {
    $.ajax({
        type: "GET",
        dataType: 'json',
        url: "/warden/realtime_btc",
        success: function (data) {
            if ('cross' in data) {
                $('#fx_cross').html(data['cross']);
                $('#fx_rate').html(data['fx_rate'].toLocaleString('en-US', { style: 'decimal', maximumFractionDigits: 2, minimumFractionDigits: 2 })).fadeTo(100, 0.3, function () { $(this).fadeTo(500, 1.0); });
                $('#btc_fx').html(data['btc_fx'].toLocaleString('en-US', { style: 'decimal', maximumFractionDigits: 2, minimumFractionDigits: 2 })).fadeTo(100, 0.3, function () { $(this).fadeTo(500, 1.0); });;
                $('#btc_usd').html(data['btc_usd'].toLocaleString('en-US', { style: 'decimal', maximumFractionDigits: 2, minimumFractionDigits: 2 })).fadeTo(100, 0.3, function () { $(this).fadeTo(500, 1.0); });
            } else {
                $('#fx_cross').html(data);
            }

        },
        error: function (xhr, status, error) {
            console.log("Error on fx request")
        }
    });
};

function check_activity() {
    $.ajax({
        type: "GET",
        dataType: 'json',
        url: "/warden/check_activity",
        success: function (data) {
            if (data == true) {
                $('#alertsection').html("<div class='alert alert-danger'>Activity Detected in one or more wallets. Refresh Page.</div>")
            }
        },
        error: function (xhr, status, error) {
            console.log("Error on activity check request")
        }
    });
};


function get_version() {
    $.ajax({
        type: "GET",
        dataType: 'json',
        url: "/warden/gitreleases",
        success: function (data) {
            $('#version').html("<p>Latest Version " + data[0]['tag_name'] + "</p>")
        },
        error: function (xhr, status, error) {
            console.log("Error on gitcheck")
        }
    });
};




function test_tor() {
    $.ajax({
        type: "GET",
        dataType: 'json',
        url: "/warden/testtor",
        success: function (data) {
            console.log("[Check Tor] ajax request: OK");
            if (data.status) {
                html_tor = "<span style='color: lightgreen;' data-toggle='tooltip' data-placement='bottom' title='Tor Enabled (" + data.post_proxy.origin + ") Ping time " + data.post_proxy_ping + "'><i class='fas fa-lg fa-user-shield'></i>&nbsp;&nbsp;&nbsp;&nbsp;Tor running</span>"
                $('[data-toggle="tooltip"]').tooltip()
            } else {
                html_tor = "<span class='text-warning'><i class='fas fa-lg fa-user-shield'></i>&nbsp;&nbsp;&nbsp;&nbsp;Tor Disabled</span>"
            }
            $('#tor_span').html(html_tor);
        },
        error: function (xhr, status, error) {
            html_tor = "<span class='text-warning'><i class='fas fa-lg fa-user-shield'></i>&nbsp;&nbsp;&nbsp;&nbsp;Tor Disabled</span>"
            $('#tor_span').html(html_tor);
        }
    });
}
