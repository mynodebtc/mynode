# Class to include several price providers that work together to update a
# list of pricing databases
# The databases are saved in the pickle format as pandas df for later use
# The field dictionary is a list of column names for the provider to
# associate with the standardized field names for the dataframe
# Standardized field names:
# open, high, low, close, volume
import json
import os
import sys
import urllib
# Different import for Python 2 and 3
try:
    from urllib.parse import urlparse
except ImportError:
    from urlparse import urlparse
    import urllib2
from datetime import datetime, timedelta

from warden_decorators import MWT

from time import time

import pandas as pd
import requests

BASE_DIR = '/var/www/mynode/warden'


@MWT(timeout=60)
def test_tor():
    response = {}
    session = requests.session()
    try:
        time_before = time()  # Save Ping time to compare
        r = session.get("http://httpbin.org/ip")
        time_after = time()
        pre_proxy_ping = time_after - time_before
        pre_proxy = r.json()
    except Exception as e:
        pre_proxy = pre_proxy_ping = "Connection Error: " + str(e)

    # Activate TOR proxies
    session.proxies = {
        "http": "socks5h://localhost:9050",
        "https": "socks5h://localhost:9050",
    }
    try:
        time_before = time()  # Save Ping time to compare
        r = session.get("http://httpbin.org/ip")
        time_after = time()
        post_proxy_ping = time_after - time_before
        post_proxy_difference = post_proxy_ping / pre_proxy_ping
        post_proxy = r.json()

        if pre_proxy["origin"] != post_proxy["origin"]:
            response = {
                "pre_proxy": pre_proxy,
                "post_proxy": post_proxy,
                "post_proxy_ping": "{0:.2f} seconds".format(post_proxy_ping),
                "pre_proxy_ping": "{0:.2f} seconds".format(pre_proxy_ping),
                "difference": "{0:.2f}".format(post_proxy_difference),
                "status": True,
            }

            return response
    except Exception as e:
        post_proxy_ping = post_proxy = "Failed checking TOR status. Error: " + str(e)

    response = {
        "pre_proxy": pre_proxy,
        "post_proxy": post_proxy,
        "post_proxy_ping": post_proxy_ping,
        "pre_proxy_ping": pre_proxy_ping,
        "difference": "-",
        "status": False,
    }
    return response


# Store TOR Status here to avoid having to check on all http requests
tor_test = test_tor()
TOR = tor_test


@MWT(timeout=10)
def tor_request(url, tor_only=True, method="get"):
    # Tor requests takes arguments:
    # url:       url to get or post
    # tor_only:  request will only be executed if tor is available
    # method:    'get or' 'post'

    tor_check = TOR
    if tor_check["status"] is True:
        try:
            # Activate TOR proxies
            session = requests.session()
            session.proxies = {
                "http": "socks5h://localhost:9050",
                "https": "socks5h://localhost:9050",
            }
            if method == "get":
                request = session.get(url, timeout=15)
            if method == "post":
                request = session.post(url, timeout=15)

        except (
            requests.exceptions.ConnectionError,
            requests.exceptions.ReadTimeout,
        ) as e:
            return "ConnectionError"
    else:
        if tor_only:
            return "Tor not available"
        try:
            if method == "get":
                request = requests.get(url, timeout=10)
            if method == "post":
                request = requests.post(url, timeout=10)

        except requests.exceptions.ConnectionError:
            return "ConnectionError"

    return request


# Generic Requests will try each of these before failing
REALTIME_PROVIDER_PRIORITY = [
    'cc_realtime', 'aa_realtime_digital', 'aa_realtime_stock',
    'fp_realtime_stock'
]
FX_RT_PROVIDER_PRIORITY = ['aa_realtime_digital', 'cc_realtime']
HISTORICAL_PROVIDER_PRIORITY = [
    'cc_digital', 'aa_digital', 'aa_stock', 'cc_fx', 'aa_fx', 'fmp_stock',
    'bitmex'
]
FX_PROVIDER_PRIORITY = ['aa_fx', 'cc_fx']

# How to include new API providers (historical prices):
# Step 1:
#     Edit the PROVIDER_LIST dictionary at the end of the file.
#     See examples there and follow a similar pattern.
#     There are 2 types of providers in that list
#     a. Providers using an html request (like aa_digital)
#     b. Providers using an internal library (like bitmex)
# Step 2:
#     Edit the price parser function to include a new if statement
#     for the new provider. Follow the examples to return a pandas
#     dataframe.
#     Errors can be returned to the self.errors variable
#     on error, return df as None (this will signal an error)
# Notes:
#     Data is saved locally to a pickle file to be used during
#     the same day. File format is <TICKER>_<PROVIDER.NAME>.price
#     see ./pricing_data folder for samples
# Including realtime providers:
# Step 1:
#     follow step 1 above.
# Step 2:
#     edit the realtime function to parse the date correctly and
#     return a price float


@MWT(timeout=600)
def current_path():
    return(BASE_DIR)

# _____________________________________________
# Classes go here
# _____________________________________________


class PriceProvider:
    # This class manages a list of all pricing providers
    def __init__(self,
                 name,
                 base_url,
                 ticker_field,
                 field_dict=None,
                 doc_link=None,
                 replace_ticker=None):
        # field dict includes all fields to be passed to the URL
        # for example, for Alphavantage
        # name = 'Alphavantage_digital'
        # base-url = 'https://www.alphavantage.co/query'
        # ticker_field = 'symbol'
        # field_dict = {'function': 'DIGITAL_CURRENCY_DAILY',
        #               'market': 'CNY',
        #               'apikey': 'demo')
        # doc_link = 'https://www.alphavantage.co/documentation/'
        # parse_dict = {'open' : '1a. open (USD)', ...}
        self.name = name.lower()
        self.base_url = base_url
        self.ticker_field = ticker_field
        self.field_dict = field_dict
        self.doc_link = doc_link
        if self.field_dict is not None:
            try:
                self.url_args = "&" + urllib.parse.urlencode(field_dict)
            except AttributeError:
                self.url_args = "&" + urllib.urlencode(field_dict)
        self.errors = []
        self.replace_ticker = replace_ticker

    @MWT(timeout=300)
    def request_data(self, ticker):
        data = None
        if self.base_url is not None:
            ticker = ticker.upper()
            globalURL = (self.base_url + "?" + self.ticker_field + "=" +
                         ticker + self.url_args)
            print(globalURL)
            # Some APIs use the ticker without a ticker field i.e. xx.xx./AAPL&...
            # in these cases, we pass the ticker field as empty
            if self.ticker_field == '':
                if self.url_args[0] == '&':
                    self.url_args = self.url_args.replace('&', '?', 1)
                globalURL = (self.base_url + "/" + ticker + self.url_args)
            # Some URLs are in the form http://www.www.www/ticker_field/extra_fields?
            if self.replace_ticker is not None:
                globalURL = self.base_url.replace('ticker_field', ticker)
            request = tor_request(globalURL)
            try:
                data = request.json()
            except Exception:
                try:  # Try again - some APIs return a json already
                    data = json.loads(request)
                except Exception as e:
                    self.errors.append(e)
        return (data)


# PriceData Class Information
# Example on how to create a ticker class (PriceData)
# provider = PROVIDER_LIST['cc_digital']
# btc = PriceData("BTC", provider)
# btc.errors:       Any error messages
# btc.provider:     Provider being used for requests
# btc.filename:     Local filename where historical prices are saved
# Other info:
# btc.ticker, btc.last_update, btc.first_update, btc.last_close
# btc.update_history(force=False)
# btc.df_fx(currency, fx_provider): returns a df with
#                                   prices and fx conversions
# btc.price_ondate(date)
# btc.price_parser(): do not use directly. This is used to parse
#                     the requested data from the API provider
# btc.realtime(provider): returns realtime price (float)
class PriceData():
    # All methods related to a ticker
    def __init__(self, ticker, provider):
        # providers is a list of pricing providers
        # ex: ['alphavantage', 'Yahoo']
        self.ticker = ticker.upper()
        self.provider = provider
        self.filename = ("thewarden/pricing_engine/pricing_data/" +
                         self.ticker + "_" + provider.name + ".price")
        self.filename = os.path.join(current_path(), self.filename)
        self.errors = []
        # makesure file path exists
        try:
            os.makedirs(os.path.dirname(self.filename))
        except OSError as e:
            if e.errno != 17:
                raise
        # Try to read from file and check how recent it is
        try:
            today = datetime.now().date()
            filetime = datetime.fromtimestamp(os.path.getctime(self.filename))
            if filetime.date() == today:
                self.df = pd.read_pickle(self.filename)
            else:
                self.df = self.update_history()
        except Exception:
            self.df = self.update_history()

        try:
            self.last_update = self.df.index.max()
            self.first_update = self.df.index.min()
            self.last_close = self.df.head(1).close[0]
        except AttributeError as e:
            self.errors.append(e)
            self.last_update = self.first_update = self.last_close = None

    @MWT(timeout=600)
    def update_history(self, force=False):
        # Check first if file exists and if fresh
        # The line below skips history for providers that have realtime in name
        if 'realtime' in self.provider.name:
            return None
        if not force:
            try:
                # Check if saved file is recent enough to be used
                # Local file has to have a modified time in today
                today = datetime.now().date()
                filetime = datetime.fromtimestamp(
                    os.path.getctime(self.filename))
                if filetime.date() == today:
                    price_pickle = pd.read_pickle(self.filename)
                    return (price_pickle)
            except Exception as e:
                pass
        # File not found ot not new. Need to update the matrix
        # Cycle through the provider list until there's satisfactory data
        price_request = self.provider.request_data(self.ticker)
        # Parse and save
        df = self.price_parser(price_request, self.provider)
        if df is None:
            self.errors.append(
                "Empty df for " + self.ticker + " using " + self.provider.name)
            return (None)
        df.sort_index(ascending=False, inplace=True)
        df.index = pd.to_datetime(df.index)
        df.to_pickle(self.filename)
        # Refresh the class - reinitialize
        return (df)

    @MWT(timeout=600)
    def df_fx(self, currency, fx_provider):
        try:
            # First get the df from this currency
            if currency != 'USD':
                fx = PriceData(currency, fx_provider)
                fx.df = fx.df.rename(columns={'close': 'fx_close'})
                fx.df["fx_close"] = pd.to_numeric(fx.df.fx_close,
                                                  errors='coerce')
                # Merge the two dfs:
                merge_df = pd.merge(self.df, fx.df, on='date', how='inner')
                merge_df['close'] = merge_df['close'].astype(float)
                merge_df['close_converted'] = merge_df['close'] * merge_df[
                    'fx_close']
                return (merge_df)
            else:  # If currency is USD no conversion is needed - prices are all in USD
                self.df['fx_close'] = 1
                self.df['close_converted'] = self.df['close'].astype(float)
                return (self.df)
        except Exception as e:
            self.errors.append(e)
            return (None)

    @MWT(timeout=600)
    def price_ondate(self, date_input):
        try:
            dt = pd.to_datetime(date_input)
            idx = self.df.iloc[self.df.index.get_loc(dt, method='nearest')]
            return (idx)
        except Exception as e:
            self.errors.append(
                "Error getting price on date " + date_input + " for " + self.ticker + ". Error " + e
            )
            return (None)

    def price_parser(self, data, provider):
        # Parse the pricing of a specific API provider so it is in a
        # standard pandas df format that can be used and merged.
        # WHEN ADDING NEW APIs, this is the main function that needs to be
        # updated since each API has a different price format
        # Standard format is:
        # date (index), close, open, high, low, volume
        # Provider: alphavantagedigital
        if provider.name == 'alphavantagedigital':
            try:
                df = pd.DataFrame.from_dict(
                    data['Time Series (Digital Currency Daily)'],
                    orient="index")
                df = df.rename(
                    columns={
                        '4a. close (USD)': 'close',
                        '1a. open (USD)': 'open',
                        '2a. high (USD)': 'high',
                        '3a. low (USD)': 'low',
                        '5. volume': 'volume'
                    })
                df_save = df[['close', 'open', 'high', 'low', 'volume']]
                df.index.names = ['date']
            except Exception as e:
                self.errors.append(e)
                df_save = None
            return (df_save)

        # Provider: alphavantagestocks
        if provider.name == 'alphavantagestock':
            try:
                df = pd.DataFrame.from_dict(data['Time Series (Daily)'],
                                            orient="index")
                df = df.rename(
                    columns={
                        '4. close': 'close',
                        '1. open': 'open',
                        '2. high': 'high',
                        '3. low': 'low',
                        '5. volume': 'volume'
                    })
                df_save = df[['close', 'open', 'high', 'low', 'volume']]
                df.index.names = ['date']
            except Exception as e:
                self.errors.append(e)
                df_save = None
            return (df_save)

        # Provider: fmpstocks
        if provider.name == 'financialmodelingprep':
            try:
                df = pd.DataFrame.from_records(data['historical'])
                df = df.rename(
                    columns={
                        'close': 'close',
                        'open': 'open',
                        'high': 'high',
                        'low': 'low',
                        'volume': 'volume'
                    })
                df.set_index('date', inplace=True)
                df_save = df[['close', 'open', 'high', 'low', 'volume']]
            except Exception as e:
                self.errors.append(e)
                df_save = None
            return (df_save)

        # Provider:
        if provider.name == 'alphavantagefx':
            try:
                df = pd.DataFrame.from_dict(data['Time Series FX (Daily)'],
                                            orient="index")
                df = df.rename(
                    columns={
                        '4. close': 'close',
                        '1. open': 'open',
                        '2. high': 'high',
                        '3. low': 'low'
                    })
                df_save = df[['close', 'open', 'high', 'low']]
                df.index.names = ['date']
            except Exception as e:
                self.errors.append(e)
                df_save = None
            return (df_save)

        # CryptoCompare Digital and FX use the same parser
        if provider.name == 'ccdigital' or provider.name == 'ccfx':
            try:
                df = pd.DataFrame.from_dict(data['Data'])
                df = df.rename(columns={'time': 'date'})
                df['date'] = pd.to_datetime(df['date'], unit='s')
                df.set_index('date', inplace=True)
                df_save = df[['close', 'open', 'high', 'low']]
            except Exception as e:
                self.errors.append(e)
                df_save = None
            return (df_save)

        # If no name is found, return None
        return None

    @MWT(timeout=30)
    def realtime(self, rt_provider):
        # This is the parser for realtime prices.
        # Data should be parsed so only the price is returned
        price_request = rt_provider.request_data(self.ticker)
        print("-----")
        print(price_request)
        price = None
        if rt_provider.name == 'ccrealtime':
            try:
                price = (price_request['USD'])
            except Exception as e:
                self.errors.append(e)

        if rt_provider.name == 'aarealtime':
            try:
                price = (price_request['Realtime Currency Exchange Rate']
                         ['5. Exchange Rate'])
            except Exception:
                try:
                    price = (price_request['price_data']['last_close'])
                except Exception as e:
                    self.errors.append(e)

        if rt_provider.name == 'aarealtimestock':
            try:
                price = (price_request['Global Quote']['05. price'])
            except Exception:
                try:
                    price = (price_request['price_data']['last_close'])
                except Exception as e:
                    self.errors.append(e)

        if rt_provider.name == 'ccrealtimefull':
            try:
                price = (price_request['RAW'][self.ticker]['USD'])
            except Exception as e:
                self.errors.append(e)

        if rt_provider.name == 'fprealtimestock':
            try:
                price = (price_request['price'])
            except Exception as e:
                self.errors.append(e)

        return price


@MWT(timeout=600)
class ApiKeys():
    # returns current stored keys in the api_keys.conf file
    # makesure file path exists
    def __init__(self):
        self.filename = 'thewarden/pricing_engine/api_keys.conf'
        try:
            os.makedirs(os.path.dirname(self.filename))
        except OSError as e:
            if e.errno != 17:
                raise

        self.filename = os.path.join(current_path(), self.filename)

    def loader(self):
        if os.path.exists(self.filename):
            try:
                with open(self.filename, 'r') as fp:
                    data = json.load(fp)
                    return (data)
            except Exception as e:
                pass
        else:
            # File not found, let's construct a new one
            empty_api = {
                "alphavantage": {"api_key": "AA_TEMP_APIKEY"},
                "bitmex": {"api_key": None, "api_secret": None},
                "dojo": {"onion": None, "api_key": None, "token": "error"}
            }
            return (empty_api)

    def saver(self, api_dict):
        try:
            with open(self.filename, 'w') as fp:
                json.dump(api_dict, fp)
        except Exception:
            pass


# Class instance with api keys loader and saver
api_keys_class = ApiKeys()
api_keys = api_keys_class.loader()


# Loop through all providers to get the first non-empty df
def price_data(ticker):
    GBTC_PROVIDER_PRIORITY = [
        'aa_stock', 'cc_fx', 'aa_fx', 'fmp_stock',
        'bitmex'
    ]
    if ticker == 'GBTC':
        provider_list = GBTC_PROVIDER_PRIORITY
    else:
        provider_list = HISTORICAL_PROVIDER_PRIORITY

    for provider in provider_list:
        price_data = PriceData(ticker, PROVIDER_LIST[provider])
        if price_data.df is not None:
            break
    return (price_data)


# Returns price data in current user's currency
def price_data_fx(ticker):
    from warden import (FX, FX_RATE)
    GBTC_PROVIDER_PRIORITY = [
        'aa_stock', 'cc_fx', 'aa_fx', 'fmp_stock',
        'bitmex'
    ]
    if ticker == 'GBTC':
        provider_list = GBTC_PROVIDER_PRIORITY
    else:
        provider_list = HISTORICAL_PROVIDER_PRIORITY

    for provider in provider_list:
        price_data = PriceData(ticker, PROVIDER_LIST[provider])
        if price_data.df is not None:
            break
    # Loop through FX providers until a df is filled
    for provider in FX_PROVIDER_PRIORITY:
        prices = price_data.df_fx(FX, PROVIDER_LIST[provider])
        if prices is not None:
            break
    return (prices)


# Returns realtime price for a ticker using the provider list
# Price is returned in USD
def price_data_rt(ticker, priority_list=REALTIME_PROVIDER_PRIORITY):
    if ticker == 'USD':
        return None
    for provider in priority_list:
        price_data = PriceData(ticker, PROVIDER_LIST[provider])
        if price_data.realtime(PROVIDER_LIST[provider]) is not None:
            break
    return (price_data.realtime(PROVIDER_LIST[provider]))


@MWT(timeout=300)
def GBTC_premium(price):
    # Calculates the current GBTC premium in percentage points
    # to BTC (see https://grayscale.co/bitcoin-trust/)
    SHARES = 0.00095812  # as of 8/1/2020
    fairvalue = price_data_rt("BTC") * SHARES
    premium = (price / fairvalue) - 1
    return fairvalue, premium


# Returns full realtime price for a ticker using the provider list
# Price is returned in USD
def price_grabber_rt_full(ticker, priority_list=['cc', 'aa', 'fp']):
    for provider in priority_list:
        price_data = price_data_rt_full(ticker, provider)
        if price_data is not None:
            return {'provider': provider,
                    'data': price_data}
    return None


@MWT(timeout=300)
def price_data_rt_full(ticker, provider):
    # Function to get a complete data set for realtime prices
    # Loop through the providers to get the following info:
    # price, chg, high, low, volume, mkt cap, last_update, source
    # For some specific assets, a field 'note' can be passed and
    # will replace volume and market cap at the main page
    # ex: GBTC premium can be calculated here
    # returns a list with the format:
    # price, last_update, high, low, chg, mktcap,
    # last_up_source, volume, source, notes
    # All data returned in USD
    # -----------------------------------------------------------
    # This function is used to grab a single price that was missing from
    # the multiprice request. Since this is a bit more time intensive, it's
    # separated so it can be memoized for a period of time (this price will
    # not refresh as frequently)
    # default: timeout=30
    from warden import (FX, FX_RATE)
    if provider == 'cc':
        multi_price = multiple_price_grab(ticker, 'USD,' + FX)
        try:
            # Parse the cryptocompare data
            price = multi_price["RAW"][ticker][FX]["PRICE"]
            price = float(price * FX_RATE)
            high = float(
                multi_price["RAW"][ticker][FX]["HIGHDAY"] *
                FX_RATE)
            low = float(
                multi_price["RAW"][ticker][FX]["LOWDAY"] *
                FX_RATE)
            chg = multi_price["RAW"][ticker][
                FX]["CHANGEPCT24HOUR"]
            mktcap = multi_price["DISPLAY"][ticker][
                FX]["MKTCAP"]
            volume = multi_price["DISPLAY"][ticker][
                FX]["VOLUME24HOURTO"]
            last_up_source = multi_price["RAW"][ticker][
                FX]["LASTUPDATE"]
            source = multi_price["DISPLAY"][ticker][
                FX]["LASTMARKET"]
            last_update = datetime.now()
            notes = None
            return (price, last_update, high, low, chg, mktcap, last_up_source,
                    volume, source, notes)
        except Exception:
            return (None)
    if provider == 'aa':
        try:
            globalURL = 'https://www.alphavantage.co/query?function=GLOBAL_QUOTE&apikey='
            globalURL += api_keys['alphavantage'][
                'api_key'] + '&symbol=' + ticker
            data = tor_request(globalURL).json()
            price = float(data['Global Quote']
                          ['05. price']) * FX_RATE
            high = float(
                data['Global Quote']['03. high']) * FX_RATE
            low = float(
                data['Global Quote']['04. low']) * FX_RATE
            chg = data['Global Quote']['10. change percent'].replace('%', '')
            try:
                chg = float(chg)
            except Exception:
                chg = chg
            mktcap = '-'
            volume = '-'
            last_up_source = '-'
            last_update = '-'
            source = 'Alphavantage'
            notes = None

            # Start Notes methods for specific assets. For example, for
            # GBTC we report the premium to BTC
            if ticker == 'GBTC':
                fairvalue, premium = GBTC_premium(
                    float(data['Global Quote']['05. price']))
                fairvalue = "{0:,.2f}".format(fairvalue)
                premium = "{0:,.2f}".format(premium * 100)
                notes = "Fair Value: " + fairvalue + "<br>Premium: " + premium + "%"
            return (price, last_update, high, low, chg, mktcap, last_up_source,
                    volume, source, notes)
        except Exception:
            return None

    if provider == 'fp':
        try:
            globalURL = 'https://financialmodelingprep.com/api/v3/stock/real-time-price/'
            globalURL += ticker
            data = tor_request(globalURL).json()
            price = float(data['price']) * FX_RATE
            high = '-'
            low = '-'
            chg = 0
            mktcap = '-'
            volume = '-'
            last_up_source = '-'
            last_update = '-'
            source = 'FP Modeling API'
            notes = None
            return (price, last_update, high, low, chg, mktcap, last_up_source,
                    volume, source, notes)
        except Exception:
            return None


def fxsymbol(fx, output='symbol'):
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
    filename = os.path.join(
        current_path(),
        'static/json_files/currency.json')
    with open(filename) as fx_json:
        fx_list = json.load(fx_json)
    try:
        out = fx_list[fx][output]
    except Exception:
        out = fx
    return (out)


# Gets Currency data for current user
# Setting a timeout to 10 as fx rates don't change so often
@MWT(timeout=600)
def fx_rate():
    from warden import (FX, FX_RATE)
    # This grabs the realtime current currency conversion against USD
    try:
        # get fx rate
        rate = {}
        rate['base'] = FX
        rate['symbol'] = fxsymbol(FX)
        rate['name'] = fxsymbol(FX, 'name')
        rate['name_plural'] = fxsymbol(FX, 'name_plural')
        rate['cross'] = "USD" + " / " + FX
        try:
            rate['fx_rate'] = 1 / (float(
                price_data_rt(FX, FX_RT_PROVIDER_PRIORITY)))
        except Exception:
            rate['fx_rate'] = 1
    except Exception as e:
        rate = {}
        rate['error'] = ("Error: " + str(e))
        rate['fx_rate'] = 1
    return (rate)


# For Tables that need multiple prices at the same time, it's quicker to get
# a single price request
# This will attempt to get all prices from cryptocompare api and return a single df
# If a price for a security is not found, other rt providers will be used.
@MWT(timeout=600)
def multiple_price_grab(tickers, fx):
    # tickers should be in comma sep string format like "BTC,ETH,LTC"
    baseURL = \
        "https://min-api.cryptocompare.com/data/pricemultifull?fsyms="\
        + tickers + "&tsyms=" + fx + "&&api_key=9863dbe4217d98738f4ab58137007d24d70da92031584ba31de78137e0576225"
    try:
        request = tor_request(baseURL)
    except requests.exceptions.ConnectionError:
        return ("ConnectionError")
    try:
        data = request.json()
    except AttributeError:
        data = "ConnectionError"
    return (data)


@MWT(timeout=600)
def get_price_ondate(ticker, date):
    try:
        price_class = price_data(ticker)
        price_ondate = price_class.price_ondate(date)
        return (price_ondate)
    except Exception as e:
        return (0)


@MWT(timeout=600)
def fx_price_ondate(base, cross, date):
    # Gets price conversion on date between 2 currencies
    # on a specific date
    try:
        provider = PROVIDER_LIST['cc_fx']
        if base == 'USD':
            price_base = 1
        else:
            base_class = PriceData(base, provider)
            price_base = base_class.price_ondate(date).close
        if cross == 'USD':
            price_cross = 1
        else:
            cross_class = PriceData(cross, provider)
            price_cross = cross_class.price_ondate(date).close
        conversion = float(price_cross) / float(price_base)
        return (conversion)
    except Exception:
        return (1)


# _____________________________________________
# Variables go here
# _____________________________________________
# List of API providers
# name: should be unique and contain only lowecase letters
PROVIDER_LIST = {
    'aa_digital':
    PriceProvider(name='alphavantagedigital',
                  base_url='https://www.alphavantage.co/query',
                  ticker_field='symbol',
                  field_dict={
                      'function': 'DIGITAL_CURRENCY_DAILY',
                      'market': 'USD',
                      'apikey': api_keys['alphavantage']['api_key']
                  },
                  doc_link='https://www.alphavantage.co/documentation/'),
    'aa_stock':
    PriceProvider(name='alphavantagestock',
                  base_url='https://www.alphavantage.co/query',
                  ticker_field='symbol',
                  field_dict={
                      'function': 'TIME_SERIES_DAILY',
                      'outputsize': 'full',
                      'apikey': api_keys['alphavantage']['api_key']
                  },
                  doc_link='https://www.alphavantage.co/documentation/'),
    'fmp_stock':
    PriceProvider(
        name='financialmodelingprep',
        base_url='https://financialmodelingprep.com/api/v3/historical-price-full',
        ticker_field='',
        field_dict={
            'from': '2001-01-01',
            'to:': '2099-12-31'
        },
        doc_link='https://financialmodelingprep.com/developer/docs/#Stock-Price'
    ),
    'aa_fx':
    PriceProvider(name='alphavantagefx',
                  base_url='https://www.alphavantage.co/query',
                  ticker_field='to_symbol',
                  field_dict={
                      'function': 'FX_DAILY',
                      'outputsize': 'full',
                      'from_symbol': 'USD',
                      'apikey': api_keys['alphavantage']['api_key']
                  },
                  doc_link='https://www.alphavantage.co/documentation/'),
    'cc_digital':
    PriceProvider(
        name='ccdigital',
        base_url='https://min-api.cryptocompare.com/data/histoday',
        ticker_field='fsym',
        field_dict={
            'tsym': 'USD',
            'allData': 'true',
            'api_key': '9863dbe4217d98738f4ab58137007d24d70da92031584ba31de78137e0576225'
        },
        doc_link='https://min-api.cryptocompare.com/documentation?key=Historical&cat=dataHistoday'
    ),
    'cc_fx':
    PriceProvider(
        name='ccfx',
        base_url='https://min-api.cryptocompare.com/data/histoday',
        ticker_field='tsym',
        field_dict={
            'fsym': 'USD',
            'allData': 'true',
            'api_key': '9863dbe4217d98738f4ab58137007d24d70da92031584ba31de78137e0576225'
        },
        doc_link='https://min-api.cryptocompare.com/documentation?key=Historical&cat=dataHistoday'
    ),
    'bitmex':
    PriceProvider(name='bitmex',
                  base_url=None,
                  ticker_field=None,
                  field_dict={
                      'api_key': api_keys['bitmex']['api_key'],
                      'api_secret': api_keys['bitmex']['api_secret'],
                      'testnet': False
                  },
                  doc_link='https://www.bitmex.com/api/explorer/'),
    'cc_realtime':
    PriceProvider(name='ccrealtime',
                  base_url='https://min-api.cryptocompare.com/data/price',
                  ticker_field='fsym',
                  field_dict={'tsyms': 'USD', 'api_key': '9863dbe4217d98738f4ab58137007d24d70da92031584ba31de78137e0576225'},
                  doc_link=None),
    'cc_realtime_full':
    PriceProvider(
        name='ccrealtimefull',
        base_url='https://min-api.cryptocompare.com/data/pricemultifull',
        ticker_field='fsyms',
        field_dict={'tsyms': 'USD', 'api_key': '9863dbe4217d98738f4ab58137007d24d70da92031584ba31de78137e0576225'},
        doc_link='https://min-api.cryptocompare.com/documentation?key=Price&cat=multipleSymbolsFullPriceEndpoint'
    ),
    'aa_realtime_digital':
    PriceProvider(name='aarealtime',
                  base_url='https://www.alphavantage.co/query',
                  ticker_field='from_currency',
                  field_dict={
                      'function': 'CURRENCY_EXCHANGE_RATE',
                      'to_currency': 'USD',
                      'apikey': api_keys['alphavantage']['api_key']
                  },
                  doc_link='https://www.alphavantage.co/documentation/'),
    'aa_realtime_stock':
    PriceProvider(name='aarealtimestock',
                  base_url='https://www.alphavantage.co/query',
                  ticker_field='symbol',
                  field_dict={
                      'function': 'GLOBAL_QUOTE',
                      'apikey': api_keys['alphavantage']['api_key']
                  },
                  doc_link='https://www.alphavantage.co/documentation/'),
    'fp_realtime_stock':
    PriceProvider(
        name='fprealtimestock',
        base_url='https://financialmodelingprep.com/api/v3/stock/real-time-price',
        ticker_field='',
        field_dict='',
        doc_link='https://financialmodelingprep.com/developer/docs/#Stock-Price'
    )
}
