import os
import subprocess
import sys
import codecs
import urllib


#==================================
# Python Info
#==================================
def isPython3():
    if (sys.version_info > (3, 0)):
        return True
    return False

def to_bytes(s):
    if type(s) is bytes:
        return s
    elif type(s) is str or (sys.version_info[0] < 3 and type(s) is unicode):
        return codecs.encode(s, 'utf-8', 'ignore')
    else:
        raise TypeError("to_bytes: Expected bytes or string, but got %s." % type(s))

def to_string(s):
    b = to_bytes(s)
    return b.decode("utf-8")

def quote_plus(s):
    if (sys.version_info > (3, 0)):
        return urllib.parse.quote_plus(s)
    else:
        return urllib.quote_plus(s)

def unquote_plus(s):
    if (sys.version_info > (3, 0)):
        return urllib.parse.unquote_plus(s)
    else:
        return urllib.unquote_plus(s)

#==================================
# Utilities
#==================================
def get_file_contents(filename):
    contents = "UNKNOWN"
    try:
        with open(filename, "r") as f:
            contents = f.read().strip()
    except:
        contents = "ERROR"
    return to_bytes(contents)

def set_file_contents(filename, data):
    data = data.replace('\r\n','\n')
    try:
        with open(filename, "w") as f:
            f.write(data)
        os.system("sync")
        return True
    except:
        return False
    return False


#==================================
# Log functions (non-systemd based)
#==================================
def get_file_log(file_path):
    status_log = ""

    if not os.path.isfile(file_path):
        return "MISSING FILE"

    try:
        status_log = subprocess.check_output(["tail","-n","200",file_path]).decode("utf8")
        lines = status_log.split('\n')
        lines.reverse()
        status_log = '\n'.join(lines)
    except Exception as e:
        status_log = "ERROR ({})".format(str(e))
    return status_log


#==================================
# Data Storage Functions
#==================================
def set_data(key, value):
    r = redis.Redis(host='localhost', port=6379, db=0)
    mynode_key = "mynode_" + key
    return r.set(mynode_key, value)

def get_data(key):
    r = redis.Redis(host='localhost', port=6379, db=0)
    mynode_key = "mynode_" + key
    return r.get(mynode_key)


#==================================
# UI Format Functions
#==================================
def format_sat_amount(amount):
    try:
        r = "{:,}".format(int(amount))
    except:
        r = amount
    return r