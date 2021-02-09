$(document).ready(function () {
    createcharts(navchartjs);
});

function createcharts(data) {

    var myChart = Highcharts.stockChart('portchart', {
        credits: {
            text: "Historical Portfolio Chart (" + fx + ")"
        },
        chart: {
            zoomType: 'x',
            backgroundColor: "#FAFAFA",
        },
        rangeSelector: {
            selected: 2
        },
        title: {
            text: 'Portfolio Value over time'
        },
        subtitle: {
            text: document.ontouchstart === undefined ?
                'Click and drag in the plot area to zoom in' : 'Pinch the chart to zoom in'
        },
        xAxis: [
            {
                type: 'datetime',
                id: 'x1'
            },
            {
                type: 'datetime',
                id: 'x2'
            },
        ],
        yAxis: [
            {
                title: {
                    text: 'NAV'
                },
                height: '35%',
                lineWidth: 2,
                opposite: true,
                startOnTick: false,
                endOnTick: false
            },
            {
                title: {
                    text: 'Portfolio Market Value and Cost Basis (' + fx + ')'
                },
                lineWidth: 4,
                top: '35%',
                height: '35%',
                offset: 0,
                startOnTick: false,
                endOnTick: false
            }, {
                title: {
                    text: 'PnL compared to Cost basis (' + fx + ')'
                },
                lineWidth: 2,
                top: '70%',
                height: '30%',
                offset: 0,
                opposite: true,
                startOnTick: false,
                endOnTick: false
            }],
        legend: {
            enabled: false
        },
        plotOptions: {
            area: {
                fillColor: {
                    linearGradient: {
                        x1: 0,
                        y1: 0,
                        x2: 0,
                        y2: 1
                    },
                    stops: [
                        [0, Highcharts.getOptions().colors[0]],
                        [1, Highcharts.Color(Highcharts.getOptions().colors[0]).setOpacity(0).get('rgba')]
                    ]
                },
                marker: {
                    radius: 2
                },
                lineWidth: 1,
                states: {
                    hover: {
                        lineWidth: 1
                    }
                },
                threshold: null
            }
        },


        series: [
            {
                type: 'line',
                dataGrouping: {
                    enabled: false
                },
                name: 'NAV [100 = first trade date]',
                yAxis: 0,
                // The line below maps the dictionary coming from Python into
                // the data needed for highcharts. It's weird but the *1 is
                // needed, otherwise the date does not show on chart.
                data: Object.keys(navchartjs).map((key) => [((key * 1)), navchartjs[key]]),
                turboThreshold: 0,
                tooltip: {
                    pointFormat: "NAV (first trade=100): {point.y:,.0f}"
                },
            },
            {
                type: 'line',
                dataGrouping: {
                    enabled: false
                },
                name: 'Portfolio Value (' + fx + ')',
                yAxis: 1,
                // The line below maps the dictionary coming from Python into
                // the data needed for highcharts. It's weird but the *1 is
                // needed, otherwise the date does not show on chart.
                data: Object.keys(portchartjs['PORT_fx_pos']).map((key) => [((key * 1)), portchartjs['PORT_fx_pos'][key]]),
                turboThreshold: 0,
                tooltip: {
                    pointFormat: "Portfolio Market Value: " + fx + " {point.y:,.0f}"
                },
            },
            {
                type: 'line',
                dataGrouping: {
                    enabled: false
                },
                name: 'Cost Basis',
                color: '#8CADE1', // Cost basis line is orange and thicker
                lineWidth: 2,
                dashStyle: 'ShortDash',
                yAxis: 1,
                // The line below maps the dictionary coming from Python into
                // the data needed for highcharts. It's weird but the *1 is
                // needed, otherwise the date does not show on chart.
                data: Object.keys(portchartjs['PORT_ac_CFs_fx']).map((key) => [((key * 1)), portchartjs['PORT_ac_CFs_fx'][key]]),
                turboThreshold: 0,
                tooltip: {
                    pointFormat: "Portfolio Cost Basis: " + fx + "{point.y:,.0f}"
                },
            },
            {
                type: 'column',
                dataGrouping: {
                    enabled: false
                },
                name: 'PnL compared to Cost basis',
                yAxis: 2,
                // The line below maps the dictionary coming from Python into
                // the data needed for highcharts. It's weird but the *1 is
                // needed, otherwise the date does not show on chart.
                data: Object.keys(portchartjs['ac_pnl_fx']).map((key) => [((key * 1)), portchartjs['ac_pnl_fx'][key]]),
                turboThreshold: 0,
                tooltip: {
                    pointFormat: "PnL compared to Cost Basis: " + fx + "{point.y:,.0f}"
                },
            }
        ]
    });


};
