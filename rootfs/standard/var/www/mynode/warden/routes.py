# IMPORTS for WARden
# -------------------------------------------------
from flask import Blueprint, redirect, render_template, flash, Flask, url_for
from warden import (list_specter_wallets,
                    warden_metadata, positions,
                    positions_dynamic, FX, FX_RATE, get_price_ondate,
                    generatenav, current_path, specter_df, current_user)


from warden_pricing_engine import (test_tor, tor_request, price_data_rt)

from datetime import datetime
from dateutil.relativedelta import relativedelta
import jinja2
import time
import simplejson
import pandas as pd
import numpy as np
import json
import os


warden = Blueprint("warden",
                   __name__,
                   template_folder='templates',
                   url_prefix='/warden',
                   static_folder='static',
                   static_url_path='/warden_static')

# current path:
# /var/www/mynode

# START WARDEN ROUTES ----------------------------------------

# Support method to check if donation was acknowledged


def donate_check():
    counter_file = os.path.join(current_path(),
                                'static/json_files/counter.json')
    donated = False
    try:
        with open(counter_file) as data_file:
            json_all = json.loads(data_file.read())
        if json_all == "donated":
            donated = True
    except Exception:
        donated = False
    return (donated)


# Support method to check for specter wallets
def have_specter_wallets():
    wallets = list_specter_wallets()
    if (wallets == []) or (wallets == None):
        return False
    return True


# Main page for WARden
@warden.route("/", methods=['GET'])
@warden.route("/warden", methods=['GET'])
def warden_page():
    if have_specter_wallets() is False:
        return redirect("/warden_empty")
    # For now pass only static positions, will update prices and other
    # data through javascript after loaded. This improves load time
    # and refresh speed.
    # Get positions and prepare df for delivery
    df = positions()
    if df is None:
        return redirect("/warden_empty")
    try:
        if df.index.name != 'trade_asset_ticker':
            df.set_index('trade_asset_ticker', inplace=True)
        df = df[df['is_currency'] == 0].sort_index(ascending=True)
        df = df.to_dict(orient='index')
    # Sometimes users clicking refresh page too quickly will generate an
    # error (not sure why). The below assures to wait before continuing.
    except Exception:
        time.sleep(1)
        df = positions()
        if not df.empty:
            df.set_index('trade_asset_ticker', inplace=True)
            df = df[df['is_currency'] == 0].sort_index(ascending=True)
            df = df.to_dict(orient='index')
        else:
            return redirect("/warden_empty")

    # Open Counter, increment, send data
    counter_file = os.path.join(current_path(),
                                'static/json_files/counter.json')
    donated = False
    try:
        with open(counter_file) as data_file:
            json_all = json.loads(data_file.read())
        if json_all == "donated":
            donated = True
        else:
            counter = int(json_all)
            counter += 1
            if counter == 25:
                flash("Looks like you've been using the app frequently. " +
                      "Awesome! Consider donating.", "info")
            if counter == 50:
                flash("Open Source software is transparent and free. " +
                      "Support it. Make a donation.", "info")
            if counter == 200:
                flash("Looks like you are a frequent user of the WARden. " +
                      "Have you donated?", "info")
            if counter >= 1000:
                flash("You've opened this page 1,000 times or more. " +
                      "Really! Time to make a donation?", "danger")
            with open(counter_file, 'w') as fp:
                json.dump(counter, fp)

    except Exception:
        # File wasn't found. Create start at zero
        if not donated:
            flash("Welcome. Consider making a donation " +
                  "to support this software.", "info")
            counter = 0
            with open(counter_file, 'w') as fp:
                json.dump(counter, fp)

    alerts = False
    meta = warden_metadata()
    if isinstance(meta['old_new_df_old'], pd.DataFrame):
        if not meta['old_new_df_old'].empty:
            alerts = True
    if isinstance(meta['old_new_df_new'], pd.DataFrame):
        if not meta['old_new_df_new'].empty:
            alerts = True

    templateData = {
        "title": "Portfolio Dashboard",
        "warden_metadata": meta,
        "warden_enabled": warden_metadata()['warden_enabled'],
        "portfolio_data": df,
        "FX": FX,
        "donated": donated,
        "alerts": alerts
    }
    return (render_template('warden/warden.html', **templateData))


# Returns notification if no wallets were found at Specter
@warden.route("/warden_empty", methods=['GET'])
def warden_empty():
    templateData = {
        "title": "Empty Wallet List",
        "donated": donate_check()}
    return (render_template('warden/warden_empty.html', **templateData))


# API End Point checks for wallet activity
@warden.route("/check_activity", methods=['GET'])
def check_activity():
    alerts = False
    meta = warden_metadata()
    if isinstance(meta['old_new_df_old'], pd.DataFrame):
        if not meta['old_new_df_old'].empty:
            alerts = True
    if isinstance(meta['old_new_df_new'], pd.DataFrame):
        if not meta['old_new_df_new'].empty:
            alerts = True
    return (json.dumps(alerts))


# Donation Thank you Page
@warden.route("/donated", methods=['GET'])
def donated():
    if have_specter_wallets() is False:
        return redirect("/warden_empty")
    counter_file = os.path.join(current_path(),
                                'static/json_files/counter.json')
    templateData = {
        "title": "Thank You!",
        "donated": donate_check()}
    with open(counter_file, 'w') as fp:
        json.dump("donated", fp)
    return (render_template('warden/warden_thanks.html', **templateData))


# Returns a JSON with Test Response on TOR
@warden.route("/testtor", methods=["GET"])
def testtor():
    return json.dumps(test_tor())


# Returns a JSON with Test Response on TOR
@warden.route("/gitreleases", methods=["GET"])
def gitreleases():
    url = 'https://api.github.com/repos/pxsocs/warden_mynode/releases'
    request = tor_request(url)
    try:
        data = request.json()
    except Exception:
        try:  # Try again - some APIs return a json already
            data = json.loads(request)
        except Exception as e:
            data = json.dumps("Error getting request")

    return json.dumps(data)


# API End point
# Json for main page with realtime positions
@warden.route("/positions_json", methods=["GET"])
def positions_json():
    # Get all transactions and cost details
    # This serves the main page
    dfdyn, piedata = positions_dynamic()
    dfdyn = dfdyn.to_dict(orient='index')

    json_dict = {
        'positions': dfdyn,
        'piechart': piedata,
        'user': current_user.fx_rate_data(),
        'btc': price_data_rt("BTC") * FX_RATE
    }
    return simplejson.dumps(json_dict, ignore_nan=True)


# Returns current BTC price and FX rate for current user
# This is the function used at the layout navbar to update BTC price
# Please note that the default is to update every 20s (MWT(20) above)
@warden.route("/realtime_btc", methods=["GET"])
def realtime_btc():
    fx_rate = {'cross': 'USD', 'fx_rate': 1}
    fx_rate['btc_usd'] = price_data_rt("BTC")
    fx_rate['btc_fx'] = fx_rate['btc_usd'] * fx_rate['fx_rate']
    return json.dumps(fx_rate)


# API end point - cleans notifications and creates a new checkpoint
@warden.route("/dismiss_notification", methods=["POST"])
def dismiss_notification():
    # Run the df and clean the files (True)
    specter_df(True)
    flash("Notification dismissed. New CheckPoint created.", "success")
    return json.dumps("Done")


# API end point to return node info
# MyNode Bitcoin Data for front page
@warden.route("/node_info", methods=["GET"])
def node_info():
    # Circular imports could happen in Flask
    from mynode import (get_service_status_code, get_bitcoin_blockchain_info,
                        get_bitcoin_peers, get_bitcoin_status,
                        get_mynode_block_height,
                        get_service_status_color,
                        is_specter_enabled, app)
    # Find bitcoind status
    status = {
        'bitcoind_status_code': get_service_status_code("bitcoind"),
        'bitcoin_info': get_bitcoin_blockchain_info(),
        'bitcoin_peers': get_bitcoin_peers()}
    if status['bitcoind_status_code'] != 0:
        status['bitcoind_status_color'] = "red"
    else:
        status['bitcoind_status_color'] = "green"
        status['bitcoind_status'] = get_bitcoin_status()
        status['current_block'] = get_mynode_block_height()
    # Find Specter status
        status['specter_status'] = ""
        status['specter_status_color'] = "gray"
        if is_specter_enabled():
            status['specter_status_color'] = get_service_status_color("specter")
            status['specter_status'] = "Running"
    return simplejson.dumps(status, ignore_nan=True)


# API end point
# Function returns summary statistics for portfolio NAV and values
# Main function for portfolio page
@warden.route("/portstats", methods=["GET", "POST"])
def portstats():
    meta = {}
    # Looking to generate the following data here and return as JSON
    # for AJAX query on front page:
    # Start date, End Date, Start NAV, End NAV, Returns (1d, 1wk, 1mo, 1yr,
    # YTD), average daily return. Best day, worse day. Std dev of daily ret,
    # Higher NAV, Lower NAV + dates. Higher Port Value (date).
    data = generatenav()
    meta["start_date"] = (data.index.min()).date().strftime("%B %d, %Y")
    meta["end_date"] = data.index.max().date().strftime("%B %d, %Y")
    meta["start_nav"] = data["NAV_fx"][0]
    meta["end_nav"] = data["NAV_fx"][-1].astype(float)
    meta["max_nav"] = data["NAV_fx"].max().astype(float)
    meta["max_nav_date"] = data[
        data["NAV_fx"] == data["NAV_fx"].max()].index.strftime("%B %d, %Y")[0]
    meta["min_nav"] = data["NAV_fx"].min().astype(float)
    meta["min_nav_date"] = data[
        data["NAV_fx"] == data["NAV_fx"].min()].index.strftime("%B %d, %Y")[0]
    meta["end_portvalue"] = data["PORT_fx_pos"][-1].astype(float)
    meta["end_portvalue_usd"] = meta[
        "end_portvalue"] / FX_RATE
    meta["max_portvalue"] = data["PORT_fx_pos"].max().astype(float)
    meta["max_port_date"] = data[data["PORT_fx_pos"] == data["PORT_fx_pos"].
                                 max()].index.strftime("%B %d, %Y")[0]
    meta["min_portvalue"] = round(data["PORT_fx_pos"].min(), 0)
    meta["min_port_date"] = data[data["PORT_fx_pos"] == data["PORT_fx_pos"].
                                 min()].index.strftime("%B %d, %Y")[0]
    meta["return_SI"] = (meta["end_nav"] / meta["start_nav"]) - 1
    # Temporary fix for an issue with portfolios that are just too new
    # Create a function to handle this
    try:
        meta["return_1d"] = (meta["end_nav"] / data["NAV_fx"][-2]) - 1
    except IndexError:
        meta["return_1d"] = "-"

    try:
        meta["return_1wk"] = (meta["end_nav"] / data["NAV_fx"][-7]) - 1
    except IndexError:
        meta["return_1wk"] = "-"

    try:
        meta["return_30d"] = (meta["end_nav"] / data["NAV_fx"][-30]) - 1
    except IndexError:
        meta["return_30d"] = "-"

    try:
        meta["return_90d"] = (meta["end_nav"] / data["NAV_fx"][-90]) - 1
    except IndexError:
        meta["return_90d"] = "-"

    try:
        meta["return_ATH"] = (meta["end_nav"] / meta["max_nav"]) - 1
    except IndexError:
        meta["return_ATH"] = "-"

    try:
        yr_ago = pd.to_datetime(datetime.today() - relativedelta(years=1))
        yr_ago_NAV = data.NAV_fx[data.index.get_loc(yr_ago, method="nearest")]
        meta["return_1yr"] = meta["end_nav"] / yr_ago_NAV - 1
    except IndexError:
        meta["return_1yr"] = "-"

    # Create data for summa"age
    meta["fx"] = FX
    meta["daily"] = {}
    for days in range(1, 8):
        meta["daily"][days] = {}
        meta["daily"][days]["date"] = data.index[days * -1].date().strftime(
            "%A <br> %m/%d")
        meta["daily"][days]["nav"] = data["NAV_fx"][days * -1]
        meta["daily"][days]["nav_prev"] = data["NAV_fx"][(days + 1) * -1]
        meta["daily"][days]["perc_chg"] = (meta["daily"][days]["nav"] /
                                           meta["daily"][days]["nav_prev"]) - 1
        meta["daily"][days]["port"] = data["PORT_fx_pos"][days * -1]
        meta["daily"][days]["port_prev"] = data["PORT_fx_pos"][(days + 1) * -1]
        meta["daily"][days]["port_chg"] = (meta["daily"][days]["port"] -
                                           meta["daily"][days]["port_prev"])

    # Removes Numpy type from json - returns int instead
    def convert(o):
        if isinstance(o, np.int64):
            return int(o)
        else:
            return (o)

    # create chart data for a small NAV chart
    return simplejson.dumps(meta, ignore_nan=True, default=convert)


# Page with a single historical chart of NAV
# Include portfolio value as well as CF_sumcum()
@warden.route("/navchart")
def navchart():
    if have_specter_wallets() is False:
        return redirect("/warden_empty")
    data = generatenav()
    navchart = data[["NAV_fx"]]
    # dates need to be in Epoch time for Highcharts
    navchart.index = (navchart.index - datetime(1970, 1, 1)).total_seconds()
    navchart.index = navchart.index * 1000
    navchart.index = navchart.index.astype(np.int64)
    navchart = navchart.to_dict()
    navchart = navchart["NAV_fx"]

    port_value_chart = data[[
        "PORT_cash_value_fx", "PORT_fx_pos", "PORT_ac_CFs_fx"
    ]]
    port_value_chart["ac_pnl_fx"] = (port_value_chart["PORT_fx_pos"] -
                                     port_value_chart["PORT_ac_CFs_fx"])
    # dates need to be in Epoch time for Highcharts
    port_value_chart.index = (port_value_chart.index -
                              datetime(1970, 1, 1)).total_seconds()
    port_value_chart.index = port_value_chart.index * 1000
    port_value_chart.index = port_value_chart.index.astype(np.int64)
    port_value_chart = port_value_chart.to_dict()

    return render_template("warden/warden_navchart.html",
                           title="NAV Historical Chart",
                           navchart=navchart,
                           port_value_chart=port_value_chart,
                           fx=FX, current_user=current_user,
                           donated=donate_check())


# API end point - returns a json with NAV Chartdata
@warden.route("/navchartdatajson", methods=["GET", "POST"])
#  Creates a table with dates and NAV values
def navchartdatajson():
    data = generatenav()
    # Generate data for NAV chart
    navchart = data[["NAV_fx"]]
    # dates need to be in Epoch time for Highcharts
    navchart.index = (navchart.index - datetime(1970, 1, 1)).total_seconds()
    navchart.index = navchart.index * 1000
    navchart.index = navchart.index.astype(np.int64)
    navchart = navchart.to_dict()
    navchart = navchart["NAV_fx"]
    # Sort for HighCharts
    import collections
    navchart = collections.OrderedDict(sorted(navchart.items()))
    navchart = json.dumps(navchart)
    return navchart


# Return the price of a ticker on a given date
# Takes arguments:
# ticker:       Single ticker for filter (default = NAV)
# date:         date to get price
@warden.route("/getprice_ondate", methods=["GET"])
def getprice_ondate():
    # Get the arguments and store
    if request.method == "GET":
        date_input = request.args.get("date")
        ticker = request.args.get("ticker")
        if (not ticker) or (not date_input):
            return 0
        ticker = ticker.upper()
        get_date = datetime.strptime(date_input, "%Y-%m-%d")
        # Create price object
        try:
            price = str(get_price_ondate(ticker, get_date).close)
        except Exception as e:
            price = "Not Found. Error: " + str(e)
        return price


# -------------------------------------------------
#  START JINJA 2 Filters
# -------------------------------------------------
# Jinja2 filter to format time to a nice string
# Formating function, takes self +
# number of decimal places + a divisor
@jinja2.contextfilter
@warden.app_template_filter()
def jformat(context, n, places, divisor=1):
    if n is None:
        return "-"
    else:
        try:
            n = float(n)
            n = n / divisor
            if n == 0:
                return "-"
        except ValueError:
            return "-"
        except TypeError:
            return (n)
        try:
            form_string = "{0:,.{prec}f}".format(n, prec=places)
            return form_string
        except (ValueError, KeyError):
            return "-"


# Jinja filter - epoch to time string
@jinja2.contextfilter
@warden.app_template_filter()
def epoch(context, epoch):
    time_r = datetime.fromtimestamp(epoch).strftime("%m-%d-%Y (%H:%M)")
    return time_r


# Jinja filter - fx details
@jinja2.contextfilter
@warden.app_template_filter()
def fxsymbol(context, fx, output='symbol'):
    # Gets an FX 3 letter symbol and returns the HTML symbol
    # Sample outputs are:
    # "EUR": {
    # "symbol": "",
    # "name": "Euro",
    # "symbol_native": "",
    # "decimal_digits": 2,
    # "rounding": 0,
    # "code": "EUR",
    # "name_plural": "euros"
    try:
        from thewarden.users.utils import current_path
        filename = os.path.join(
            current_path(), 'static/json_files/currency.json')
        with open(filename) as fx_json:
            fx_list = json.load(fx_json, encoding='utf-8')
        out = fx_list[fx][output]
    except Exception:
        out = fx
    return (out)


# Jinja filter - time to time_ago
@jinja2.contextfilter
@warden.app_template_filter()
def time_ago(context, time=False):
    if type(time) is str:
        try:
            time = int(time)
        except TypeError:
            return ""
    now = datetime.now()
    if type(time) is int:
        diff = now - datetime.fromtimestamp(time)
    elif isinstance(time, datetime):
        diff = now - time
    elif not time:
        diff = now - now
    else:
        return ("")
    second_diff = diff.seconds
    day_diff = diff.days

    if day_diff < 0:
        return ""

    if day_diff == 0:
        if second_diff < 10:
            return "Just Now"
        if second_diff < 60:
            return str(int(second_diff)) + " seconds ago"
        if second_diff < 120:
            return "a minute ago"
        if second_diff < 3600:
            return str(int(second_diff / 60)) + " minutes ago"
        if second_diff < 7200:
            return "an hour ago"
        if second_diff < 86400:
            return str(int(second_diff / 3600)) + " hours ago"
    if day_diff == 1:
        return "Yesterday"
    if day_diff < 7:
        return str(int(day_diff)) + " days ago"
    if day_diff < 31:
        return str(int(day_diff / 7)) + " weeks ago"
    if day_diff < 365:
        return str(int(day_diff / 30)) + " months ago"
    return str(int(day_diff / 365)) + " years ago"

# END WARDEN ROUTES ----------------------------------------
