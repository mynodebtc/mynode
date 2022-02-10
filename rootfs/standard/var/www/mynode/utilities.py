from flask import send_from_directory
import os
import subprocess
import sys
import codecs
import urllib

mynode_logger = None

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
def touch(file_path):
    # In rare cases, touch seems to fail, so try both python and system call
    # Touch via python
    if os.path.exists(file_path):
        os.utime(file_path, None)
    else:
        open(file_path, 'a').close()
    # Touch via system
    os.system("touch {}".format(file_path))
    # Sync
    os.system("sync")

def delete_file(file_path):
    try:
        if os.path.exists(file_path):
            os.remove(file_path)
            os.system("rm -f {}".format(file_path))
    except Exception as e:
        log_message("FAILED TO DELETE {}".format(file_path))
    
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
# Logging Functions
#==================================
def log_message(msg):
    # Logs to www log
    global mynode_logger
    if mynode_logger != None:
        mynode_logger.info(msg)

def set_logger(l):
    global mynode_logger
    mynode_logger = l

def get_logger():
    global mynode_logger
    return mynode_logger


#==================================
# Log functions (non-systemd based)
#==================================
def get_file_log(file_path):
    status_log = ""

    if not os.path.isfile(file_path):
        return "MISSING FILE"

    try:
        status_log = to_string(subprocess.check_output(["tail","-n","250",file_path]).decode("utf8"))
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


#==================================
# Flask Functions
#==================================
def download_file(directory, filename, downloaded_file_name=None, as_attachment=True):
    if isPython3():
        return send_from_directory(directory=directory, path=filename, filename=None, as_attachment=as_attachment)
    else:
        return send_from_directory(directory=directory, filename=filename, as_attachment=as_attachment)
