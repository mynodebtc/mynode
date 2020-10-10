//  HELPER FUNCTION

// Slider Formatting and funcionality

$(document).ready(function () {

});



// Formatter for numbers use
// prepend for currencies, for positive / negative, include prepend = +
// Small_pos signals to hide result - this is due to small positions creating
// unrealistic breakevens (i.e. too small or too large)
function formatNumber(amount, decimalCount = 2, prepend = '', postpend = '', small_pos = 'False', up_down = false, red_green = false) {
    if (((amount == 0) | (amount == null)) | (small_pos == 'True')) {
        return '-'
    }
    try {
        var string = ''
        string += (amount).toLocaleString('en-US', { style: 'decimal', maximumFractionDigits: decimalCount, minimumFractionDigits: decimalCount })
        if ((prepend == '+') && (amount > 0)) {
            string = "+" + string
        } else if ((prepend == '+') && (amount <= 0)) {
            string = string
        } else {
            string = prepend + string
        }

        if (up_down == true) {
            if (amount > 0) {
                postpend = postpend + '&nbsp;<img src="warden_static/images/btc_up.png" width="10" height="10"></img>'
            } else if (amount < 0) {
                postpend = postpend + '&nbsp;<img src="warden_static/images/btc_down.png" width="10" height="10"></img>'
            }
        }
        if (red_green == true) {
            if (amount > 0) {
                string = "<span style='color: green'>" + string + "<span>"
            } else if (amount < 0) {
                string = "<span style='color: red'>" + string + "<span>"
            }
        }

        return (string + postpend)
    } catch (e) {
        console.log(e)
    }
};


function formatDate(date) {
    var year = date.getFullYear();

    var month = (1 + date.getMonth()).toString();
    month = month.length > 1 ? month : '0' + month;

    var day = date.getDate().toString();
    day = day.length > 1 ? day : '0' + day;

    return month + '/' + day + '/' + year;
}

var getUrlParameter = function getUrlParameter(sParam) {
    var sPageURL = window.location.search.substring(1),
        sURLVariables = sPageURL.split('&'),
        sParameterName,
        i;

    for (i = 0; i < sURLVariables.length; i++) {
        sParameterName = sURLVariables[i].split('=');

        if (sParameterName[0] === sParam) {
            return sParameterName[1] === undefined ? true : decodeURIComponent(sParameterName[1]);
        }
    }
};




function heat_color(object, inverse = false) {
    // Get all data values from our table cells making sure to ignore the first column of text
    // Use the parseInt function to convert the text string to a number


    // Let's create a heatmap on all heatmap values
    // Function to get the max value in an Array
    Array.max = function (array) {
        return Math.max.apply(Math, array);
    };

    // Function to get the min value in an Array
    Array.min = function (array) {
        return Math.min.apply(Math, array);
    };

    var counts_positive = $(object).map(function () {
        if (parseInt($(this).text()) > 0) {
            return parseInt($(this).text());
        };
    }).get();

    var counts_negative = $(object).map(function () {
        if (parseInt($(this).text()) < 0) {
            return parseInt($(this).text());
        };
    }).get();

    // run max value function and store in variable
    var max = Array.max(counts_positive);
    var min = Array.min(counts_negative) * (-1);

    n = 100; // Declare the number of groups

    // Define the ending colour, which is white
    xr = 250; // Red value
    xg = 250; // Green value
    xb = 250; // Blue value

    // Define the starting colour for positives
    yr = 165; // Red value 243
    yg = 255; // Green value 32
    yb = 165; // Blue value 117

    if (inverse == true) {
        // Define the starting colour for negatives
        yr = 80; // Red value 243
        yg = 130; // Green value 32
        yb = 200 // Blue value 117
    }

    // Define the starting colour for negatives
    nr = 255; // Red value 243
    ng = 120; // Green value 32
    nb = 120; // Blue value 117

    // Loop through each data point and calculate its % value
    $(object).each(function () {
        if (parseInt($(this).text()) > 0) {
            var val = parseInt($(this).text());
            var pos = parseInt((Math.round((val / max) * 100)).toFixed(0));
            red = parseInt((xr + ((pos * (yr - xr)) / (n - 1))).toFixed(0));
            green = parseInt((xg + ((pos * (yg - xg)) / (n - 1))).toFixed(0));
            blue = parseInt((xb + ((pos * (yb - xb)) / (n - 1))).toFixed(0));
            clr = 'rgb(' + red + ',' + green + ',' + blue + ')';
            $(this).closest('td').css({ backgroundColor: clr });
        }
        else {
            var val = parseInt($(this).text()) * (-1);
            var pos = parseInt((Math.round((val / max) * 100)).toFixed(0));
            red = parseInt((xr + ((pos * (nr - xr)) / (n - 1))).toFixed(0));
            green = parseInt((xg + ((pos * (ng - xg)) / (n - 1))).toFixed(0));
            blue = parseInt((xb + ((pos * (nb - xb)) / (n - 1))).toFixed(0));
            clr = 'rgb(' + red + ',' + green + ',' + blue + ')';
            $(this).closest('td').css({ backgroundColor: clr });
        }
    });
}


function sleep(milliseconds) {
    var start = new Date().getTime();
    for (var i = 0; i < 1e7; i++) {
        if ((new Date().getTime() - start) > milliseconds) {
            break;
        }
    }
}


function export_table(table_id) {
    var titles = [];
    var data = [];

    /*
     * Get the table headers, this will be CSV headers
     * The count of headers will be CSV string separator
     */
    $('#' + table_id + ' th').each(function () {
        var cellData = $(this).text();
        var cleanData = escape(cellData);
        var cleanData = cellData.replace(/,/g, "");
        var cleanData = cleanData.replace(/\s+/g, "  ");
        titles.push(cleanData);
    });

    /*
     * Get the actual data, this will contain all the data, in 1 array
     */
    $('#' + table_id + ' td').each(function () {
        var cellData = $(this).text();
        var cleanData = escape(cellData);
        var cleanData = cellData.replace(/,/g, "");
        var cleanData = cleanData.replace(/\s+/g, "  ");
        data.push(cleanData);
    });


    /*
     * Convert our data to CSV string
     */
    var CSVString = prepCSVRow(titles, titles.length, '');
    CSVString = prepCSVRow(data, titles.length, CSVString);

    /*
     * Make CSV downloadable
     */
    var downloadLink = document.createElement("a");
    var blob = new Blob(["\ufeff", CSVString]);
    var url = URL.createObjectURL(blob);
    downloadLink.href = url;
    downloadLink.download = "download_" + table_id + "_data.csv";

    /*
     * Actually download CSV
     */
    document.body.appendChild(downloadLink);
    downloadLink.click();
    document.body.removeChild(downloadLink);
};

/*
* Convert data array to CSV string
* @param arr {Array} - the actual data
* @param columnCount {Number} - the amount to split the data into columns
* @param initial {String} - initial string to append to CSV string
* return {String} - ready CSV string
*/
function prepCSVRow(arr, columnCount, initial) {
    var row = ''; // this will hold data
    var delimeter = ';'; // data slice separator, in excel it's `;`, in usual CSv it's `,`
    var newLine = '\n'; // newline separator for CSV row

    /*
     * Convert [1,2,3,4] into [[1,2], [3,4]] while count is 2
     * @param _arr {Array} - the actual array to split
     * @param _count {Number} - the amount to split
     * return {Array} - splitted array
     */
    function splitArray(_arr, _count) {
        var splitted = [];
        var result = [];
        _arr.forEach(function (item, idx) {
            if ((idx + 1) % _count === 0) {
                splitted.push(item);
                result.push(splitted);
                splitted = [];
            } else {
                splitted.push(item);
            }
        });
        return result;
    }
    var plainArr = splitArray(arr, columnCount);
    // don't know how to explain this
    // you just have to like follow the code
    // and you understand, it's pretty simple
    // it converts `['a', 'b', 'c']` to `a,b,c` string
    plainArr.forEach(function (arrItem) {
        arrItem.forEach(function (item, idx) {
            row += item + ((idx + 1) === arrItem.length ? '' : delimeter);
        });
        row += newLine;
    });
    return initial + row;
}

// -----------------------------------------------------------------
// HighCharts --- Create Simple charts templates
// -----------------------------------------------------------------

// PIE CHART
// receives: pie_chart (data) in format:
//          [{
//          'name': string,
//          'y': float,
//          'color': hex color
//          }, {....}]
// series_name
// target_div
function draw_pie_chart(pie_chart, series_name, target_div) {
    Highcharts.chart(target_div, {
        chart: {
            type: 'pie'
        },
        credits: {
            text: "Ⓒ Rebel",
            style: {
                fontSize: '10px',
                color: '#363636'
            },
            position: {
                align: 'right',
                y: -5
            },
            href: "http://www.rebel.com.br"
        },
        title: {
            text: null
        },
        tooltip: {
            pointFormat: '{series.name}: <b>{point.percentage:.1f}%</b>'
        },
        accessibility: {
            point: {
                valueSuffix: '%'
            }
        },
        plotOptions: {
            pie: {
                allowPointSelect: true,
                cursor: 'pointer',
                dataLabels: {
                    enabled: true,
                    format: '<b>{point.name}</b>: {point.percentage:.1f} %',
                    style: {
                        fontSize: '10px',
                        color: '#363636'
                    },
                },
            }
        },
        series: [{
            name: series_name,
            data: pie_chart
        }]
    });
}


// Draws a basic chart with limited customization
// chart_types: line, bar, etc... These are the highchart chart types
// chart_data in format :
//              [{
//              name: name,
//              data: data
//              }]
function draw_simple_chart(chart_type, bins, chart_data, name, title, subtitle, target_div) {
    Highcharts.chart(target_div, {
        chart: {
            type: chart_type
        },
        title: {
            text: title
        },
        subtitle: {
            text: subtitle
        },
        xAxis: {
            categories: bins,
            title: {
                text: null
            }
        },
        yAxis: {
            min: 0,
            title: {
                text: name,
                align: 'high'
            },
            labels: {
                overflow: 'justify'
            }
        },
        tooltip: {
            valueSuffix: ''
        },
        plotOptions: {
            bar: {
                dataLabels: {
                    enabled: true
                }
            }
        },
        legend: {
            enabled: false,
        },
        credits: {
            enabled: false
        },
        series: chart_data
    });
}


// Returns a csv from an array of objects with
// values separated by commas and rows separated by newlines
function CSV(array) {

    var result = ''
    for (var key in array) {
        if (array.hasOwnProperty(key)) {
            result += key + "," + array[key] + "\n";
        }
    }
    return result;

}

// Save txt into filename
function download(filename, text) {
    var pom = document.createElement('a');
    pom.setAttribute('href', 'data:text/plain;charset=utf-8,' + encodeURIComponent(text));
    pom.setAttribute('download', filename);

    if (document.createEvent) {
        var event = document.createEvent('MouseEvents');
        event.initEvent('click', true, true);
        pom.dispatchEvent(event);
    }
    else {
        pom.click();
    }
}

function updateURLParameter(url, param, paramVal) {
    var TheAnchor = null;
    var newAdditionalURL = "";
    var tempArray = url.split("?");
    var baseURL = tempArray[0];
    var additionalURL = tempArray[1];
    var temp = "";

    if (additionalURL) {
        var tmpAnchor = additionalURL.split("#");
        var TheParams = tmpAnchor[0];
        TheAnchor = tmpAnchor[1];
        if (TheAnchor)
            additionalURL = TheParams;

        tempArray = additionalURL.split("&");

        for (var i = 0; i < tempArray.length; i++) {
            if (tempArray[i].split('=')[0] != param) {
                newAdditionalURL += temp + tempArray[i];
                temp = "&";
            }
        }
    }
    else {
        var tmpAnchor = baseURL.split("#");
        var TheParams = tmpAnchor[0];
        TheAnchor = tmpAnchor[1];

        if (TheParams)
            baseURL = TheParams;
    }

    if (TheAnchor)
        paramVal += "#" + TheAnchor;

    var rows_txt = temp + "" + param + "=" + paramVal;
    return baseURL + "?" + newAdditionalURL + rows_txt;
}


function copyTable(el) {
    var body = document.body, range, sel;
    if (document.createRange && window.getSelection) {
        range = document.createRange();
        sel = window.getSelection();
        sel.removeAllRanges();
        try {
            range.selectNodeContents(el);
            sel.addRange(range);
        } catch (e) {
            range.selectNode(el);
            sel.addRange(range);
        }
    } else if (body.createTextRange) {
        range = body.createTextRange();
        range.moveToElementText(el);
        range.select();
    }
    document.execCommand("Copy");
}