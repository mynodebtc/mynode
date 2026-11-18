from flask import Blueprint, render_template, session, abort, Markup, request, redirect, url_for, flash, g
from config import *
import ipaddress
import json
import time
import pam
import os
import subprocess
import threading

# Globals
LOGIN_ATTEMPT_LIMIT = 5
LOGIN_ATTEMPT_WINDOW_SECONDS = 300
LOGIN_ATTEMPT_MAX_SOURCES = 1000
LOGIN_ATTEMPT_LOCAL_SOURCE = "local"
TOO_MANY_ATTEMPTS_MESSAGE = "Too Many Invalid Attempts - Wait 5 minutes"
login_attempts = {}     # source -> [count, time of first attempt in the window]
login_attempt_lock = threading.Lock()

# Exceptions
class LoginError(Exception):
   """Raised when a user is not logged in"""
   pass

# Functions
def check_logged_in():
    if is_logged_in():
        return True
    else:
        raise LoginError

def is_logged_in():
    if "logged_in" in session and session["logged_in"] == True:
        return True
    return False

def get_client_address():
    # The address the request came from, or None when it never left this device. Clients on the
    # network connect directly. Everything that arrives through this device - nginx for HTTPS and
    # for the onion service, the local desktop, a tunnel - comes from loopback; nginx passes the
    # client's address in X-Real-IP, and anything without a usable one counts as this device.
    try:
        address = request.remote_addr
    except RuntimeError:
        return None
    try:
        ip = ipaddress.ip_address(address)
    except (TypeError, ValueError):
        return None
    if not ip.is_loopback:
        return ip
    try:
        forwarded = ipaddress.ip_address(request.headers.get("X-Real-IP", "").strip())
    except ValueError:
        return None
    if forwarded.is_loopback:
        return None
    return forwarded

def is_local_client():
    return get_client_address() == None

def get_login_source():
    # Where a password attempt comes from. Attempts are counted per source, so one client
    # reaching its limit does not stop others, and everything arriving through this device
    # itself shares a single local count.
    address = get_client_address()
    if address == None:
        return LOGIN_ATTEMPT_LOCAL_SOURCE
    return str(address)

def login(password):
    source = get_login_source()

    # Count the attempt before checking the password, and refund it on success
    with login_attempt_lock:
        if get_recent_invalid_login_attempts(source) >= LOGIN_ATTEMPT_LIMIT:
            g.login_error_message = TOO_MANY_ATTEMPTS_MESSAGE
            return False
        increase_recent_login_attempts(source)

    p = pam.pam()
    if password == None or p.authenticate("admin", password) == False:
        g.login_error_message = "Invalid Password"
        return False
    else:
        with login_attempt_lock:
            decrease_recent_login_attempts(source)

        # Setup settion info
        session["logged_in"] = True
        session.permanent = True

        return True

def is_admin_password_valid(password):
    # Password prompts for logged-in actions share login()'s attempt limit
    source = get_login_source()
    with login_attempt_lock:
        if get_recent_invalid_login_attempts(source) >= LOGIN_ATTEMPT_LIMIT:
            return False
        increase_recent_login_attempts(source)

    if password == None or pam.pam().authenticate("admin", password) == False:
        return False

    with login_attempt_lock:
        decrease_recent_login_attempts(source)
    return True

def get_admin_password_error():
    with login_attempt_lock:
        if get_recent_invalid_login_attempts(get_login_source()) >= LOGIN_ATTEMPT_LIMIT:
            return TOO_MANY_ATTEMPTS_MESSAGE
    return "Invalid Password"

def logout():
    session.clear()

def handle_login_exception(e):
    return redirect("/login")

# Kept in /run (root-only tmpfs) so restarting the web UI does not reset the counts.
# Callers hold login_attempt_lock.
LOGIN_ATTEMPTS_FILE = "/run/mynode_login_attempts"

def load_login_attempts():
    global login_attempts
    try:
        with open(LOGIN_ATTEMPTS_FILE, "r") as f:
            data = json.load(f)
        login_attempts = {str(source): [int(entry[0]), float(entry[1])] for source, entry in data.items()}
    except Exception:
        login_attempts = {}

def save_login_attempts():
    try:
        tmp = LOGIN_ATTEMPTS_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(login_attempts, f)
        os.replace(tmp, LOGIN_ATTEMPTS_FILE)
    except Exception:
        pass

def remove_expired_login_attempts():
    now = time.time()
    for source in [s for s, (count, marker) in login_attempts.items() if now > marker + LOGIN_ATTEMPT_WINDOW_SECONDS]:
        del login_attempts[source]

def get_recent_invalid_login_attempts(source):
    remove_expired_login_attempts()
    if source in login_attempts:
        return login_attempts[source][0]
    return 0

def increase_recent_login_attempts(source):
    remove_expired_login_attempts()
    if source not in login_attempts:
        # Keep the table bounded: drop the oldest window if it is full
        if len(login_attempts) >= LOGIN_ATTEMPT_MAX_SOURCES:
            del login_attempts[min(login_attempts, key=lambda s: login_attempts[s][1])]
        # Mark time of first attempt so we know when the window ends
        login_attempts[source] = [0, time.time()]
    login_attempts[source][0] += 1
    save_login_attempts()

def decrease_recent_login_attempts(source):
    if source in login_attempts and login_attempts[source][0] > 0:
        login_attempts[source][0] -= 1
        save_login_attempts()

def get_login_error_message():
    return g.get("login_error_message", "Invalid Password")

load_login_attempts()
