from flask import send_from_directory
import os
import time
import json
import subprocess
import sys
import codecs
import urllib
import requests
import re
import pwd
import grp
from decimal import Decimal

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
    elif type(s) is str or (not isPython3() and type(s) is unicode):
        return codecs.encode(s, 'utf-8', 'ignore')
    else:
        raise TypeError("to_bytes: Expected bytes or string, but got %s." % type(s))

def to_string(s):
    b = to_bytes(s)
    r = b.decode("utf-8")
    return r

def quote_plus(s):
    if isPython3():
        return urllib.parse.quote_plus(s)
    else:
        return urllib.quote_plus(s)

def unquote_plus(s):
    if isPython3():
        return urllib.parse.unquote_plus(s)
    else:
        return urllib.unquote_plus(s)

#==================================
# Utilities
#==================================
def touch(file_path):
    if os.path.exists(file_path):
        os.utime(file_path, None)
    else:
        open(file_path, 'a').close()
    # Sync
    os.system("sync")

def delete_file(file_path):
    try:
        if os.path.exists(file_path):
            os.remove(file_path)
    except Exception as e:
        log_message("FAILED TO DELETE {}".format(file_path))
    
def get_file_contents(filename):
    contents = "UNKNOWN"
    try:
        with open(filename, "r") as f:
            contents = to_string(f.read()).strip()
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

# Like set_file_contents, but mode 600 and owned by owner (who must be able to read it)
def set_private_file_contents(filename, data, owner="bitcoin"):
    data = data.replace('\r\n','\n')
    try:
        fd = os.open(filename, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            os.fchmod(f.fileno(), 0o600)
            user = pwd.getpwnam(owner)
            os.fchown(f.fileno(), user.pw_uid, user.pw_gid)
            f.write(data)
        os.system("sync")
        return True
    except:
        return False
    return False


#==================================
# Cache Functions
#==================================
utilities_cached_data = {}

def is_cached(key, refresh_time=0): # Don't timeout by default
    global utilities_cached_data
    cache_time_key = key + "_cache_time"
    now_time = int(time.time())
    if key in utilities_cached_data:
        if refresh_time != 0 and cache_time_key in utilities_cached_data:
            if utilities_cached_data[cache_time_key] + refresh_time < now_time:
                return False
        return True
    else:
        return False

def get_cached_data(key):
    global utilities_cached_data
    if key in utilities_cached_data:
        return utilities_cached_data[key]
    return None

def set_cached_data(key, value):
    update_cached_data(key, value)

def update_cached_data(key, value):
    global utilities_cached_data
    cache_time_key = key + "_cache_time"
    now_time = int(time.time())
    utilities_cached_data[key] = value
    utilities_cached_data[cache_time_key] = now_time

def clear_cached_data(key):
    global utilities_cached_data
    cache_time_key = key + "_cache_time"
    utilities_cached_data.pop(key, None)
    utilities_cached_data.pop(cache_time_key, None)

def increment_cached_integer(key):
    if is_cached(key):
        val = get_cached_data(key)
        update_cached_data(key, val+1)
    else:
        update_cached_data(key, 1)


#==================================
# Read and Write Python Dictionaries to JSON Cache Functions
#==================================
def decimal_serializer(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    return TypeError("Type not Serializable")

def set_dictionary_file_cache(data, file_path):
    try:
        with open(file_path, 'w') as file:
            json.dump(data, file, default=decimal_serializer)
        return True
    except Exception as e:
        log_message("ERROR set_dictionary_file_cache ({}):{} ".format(file_path, str(e)))
        log_message(str(data))
        return False

def get_dictionary_file_cache(file_path):
    try:
        with open(file_path) as file:
            data = json.load(file)
        return data
    except Exception as e:
        log_message("ERROR get_dictionary_file_cache ({}): {}".format(file_path, str(e)))
        return None

#==================================
# Input Validation
#==================================
# Values that get built into file paths or passed as command arguments.
# App and setting names are plain identifiers. Wallet names also allow a dot,
# since bitcoind uses names like wallet.dat.
SAFE_NAME_REGEX = re.compile(r"^[A-Za-z0-9_]+$")
SAFE_WALLET_NAME_REGEX = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.]*$")
SAFE_VERSION_REGEX = re.compile(r"^[A-Za-z0-9_.-]+$")
SAFE_TOWER_REGEX = re.compile(r"^[A-Za-z0-9_.:@-]+$")

def is_safe_name(name):
    if name == None:
        return False
    return SAFE_NAME_REGEX.match(name) != None

def is_safe_wallet_name(name):
    if name == None:
        return False
    if ".." in name:
        return False
    return SAFE_WALLET_NAME_REGEX.match(name) != None

def is_safe_download_url(url):
    if url == None or url == "":
        return False
    return url.startswith("http://") or url.startswith("https://")

def is_safe_version(version):
    if version == None or len(version) > 64:
        return False
    if version.startswith("-") or version.startswith("."):
        return False
    if ".." in version:
        return False
    return SAFE_VERSION_REGEX.match(version) != None

def is_safe_tower(tower):
    if tower == None or tower == "":
        return False
    if tower.startswith("-"):
        return False
    return SAFE_TOWER_REGEX.match(tower) != None

#==================================
# Settings File Functions
#==================================
def create_settings_file(name):
    from drive_info import is_mynode_drive_mounted

    if not is_safe_name(name):
        log_message("Refusing to create settings file for name: {}".format(name))
        return

    folder_1="/home/bitcoin/.mynode/"
    folder_2="/mnt/hdd/mynode/settings/"
    path_1="{}{}".format(folder_1, name)
    path_2="{}{}".format(folder_2, name)
    touch(path_1)
    if is_mynode_drive_mounted():
        touch(path_2)

def delete_settings_file(name):
    if not is_safe_name(name):
        log_message("Refusing to delete settings file for name: {}".format(name))
        return

    folder_1="/home/bitcoin/.mynode/"
    folder_2="/mnt/hdd/mynode/settings/"
    path_1="{}{}".format(folder_1, name)
    path_2="{}{}".format(folder_2, name)
    path_3="{}.{}".format(folder_1, name)
    path_4="{}.{}".format(folder_2, name)
    delete_file(path_1)
    delete_file(path_2)
    delete_file(path_3)
    delete_file(path_4)

def settings_file_exists(name):
    from drive_info import is_mynode_drive_mounted

    if not is_safe_name(name):
        return False

    folder_1="/home/bitcoin/.mynode/"
    folder_2="/mnt/hdd/mynode/settings/"
    path_1="{}{}".format(folder_1, name)
    path_2="{}{}".format(folder_2, name)
    path_3="{}.{}".format(folder_1, name)
    path_4="{}.{}".format(folder_2, name)
    
    # Migrate hidden files to non-hidden
    if os.path.isfile(path_3) or os.path.isfile(path_4):
        # Make sure backup file is in place
        touch(path_1)
        if is_mynode_drive_mounted():
            touch(path_2)
        delete_file(path_3)
        delete_file(path_4)

    if os.path.isfile(path_1) and os.path.isfile(path_2):
        return True
    elif os.path.isfile(path_1) or os.path.isfile(path_2):
        # Make sure backup file is in place
        touch(path_1)
        if is_mynode_drive_mounted():
            touch(path_2)
        return True
    
    return False


#==================================
# Logging Functions
#==================================
def log_message(msg):
    # Logs to www log
    global mynode_logger
    if mynode_logger != None:
        print(msg)
        mynode_logger.info(msg)

def set_logger(logger):
    global mynode_logger
    mynode_logger = logger

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
def download_file(directory, filename, as_attachment=True):
    if isPython3():
        return send_from_directory(directory=directory, path=filename, as_attachment=as_attachment)
    else:
        return send_from_directory(directory=directory, filename=filename, as_attachment=as_attachment)

#==================================
# Hashing Functions
#==================================
def get_md5_file_hash(path):
    import hashlib
    if not os.path.isfile(path):
        return "MISSING_FILE"
    try:
        return hashlib.md5(open(path,'rb').read()).hexdigest()
    except Exception as e:
        return "ERROR ({})".format(e)

#==================================
# Network Functions
#==================================
def make_tor_request(url, data, file_data=None, max_retries=5, fallback_to_ip=True, fail_delay=5):
    # Return data
    r = None

    # Setup tor proxy
    session = requests.session()
    session.proxies = {}
    session.proxies['http'] = 'socks5h://localhost:9050'
    session.proxies['https'] = 'socks5h://localhost:9050'

    # Check In
    for fail_count in range(max_retries):
        try:
            # Use tor for check in unless there have been tor 5 failures in a row
            r = None
            if fallback_to_ip and fail_count >= (max_retries - 1):
                r = requests.post(url, data=data, files=file_data, timeout=20)
            else:
                r = session.post(url, data=data, files=file_data, timeout=20)
            
            if r.status_code == 200:
                return r
            else:
                log_message("Connection to {} failed. Retrying... Code {}".format(url, r.status_code))
        except Exception as e:
            log_message("Connection to {} failed. Retrying... Exception {}".format(url, e))

        # Check in failed, try again
        time.sleep(fail_delay)

    return r

#==================================
# Linux Functions
#==================================
def run_linux_cmd_args(args, ignore_failure=False, print_command=False):
    try:
        output = to_string(subprocess.check_output(args))
        if print_command:
            print(" ".join(args))
            if output != "":
                print(output)
        return output
    except Exception as e:
        if not ignore_failure:
            log_message("ERROR in run_linux_cmd_args: {} ({})".format(" ".join(args), str(e)))
        return ""

def run_linux_cmd(args, ignore_failure=False, print_command=False):
    cmd = " ".join(args)
    try:
        output = to_string(subprocess.check_output(args))
        if print_command:
            print(cmd)
            if output != "":
                print(output)
        return output
    except Exception as e:
        print("Linux Command Failed!!!")
        print("   Command: {}".format(cmd))
        print("   Error: {}".format(str(e)))
        if ignore_failure:
            return "ERROR"
        else:
            raise e
    return "UNKNOWN"

def linux_user_exists(username):
    try:
        pwd.getpwnam(username)
        return True
    except:
        pass
    return False

# May need to add options for passwords, making home folder, etc... later. For now, no passwd.
def linux_create_user(username, make_home_folder=False):
    if linux_user_exists(username):
        return
    cmd = ["useradd"]
    if make_home_folder:
        cmd.append("-m")
    cmd += ["-s", "/bin/bash", username]
    run_linux_cmd(cmd, ignore_failure=True, print_command=True)

def user_is_in_group(username, group):
    try:
        group_info = grp.getgrnam(group)
        for grpusr in group_info.gr_mem:
            if username == grpusr:
                return True
    except:
        return False
    return False

def add_user_to_group(username, group):
    if not user_is_in_group(username, group):
        run_linux_cmd(["adduser", username, group], print_command=True)