import os
import subprocess

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
    return contents

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