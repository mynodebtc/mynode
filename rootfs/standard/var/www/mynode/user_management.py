from flask import Blueprint, render_template, session, abort, Markup, request, redirect, send_from_directory, url_for, flash
from config import *
import time
import pam
import os
import subprocess

# Globals
recent_invalid_login_attempt = 0
recent_invalid_login_time_marker = 0
login_error_message = ""

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

def login(password):
    global login_error_message

    if get_recent_invalid_login_attempts() >= 5:
        login_error_message = "Too Many Invalid Attempts - Wait 5 minutes"
        return False

    p = pam.pam()
    if password == None or p.authenticate("admin", password) == False:
        login_error_message = "Invalid Password"
        increase_recent_invalid_login_attempts()
        return False
    else:
        # Setup settion info
        session["logged_in"] = True
        session.permanent = True

        # Call change password to ensure hash files are up to date
        subprocess.call(['/usr/bin/mynode_chpasswd.sh', password])

        return True

def logout():
    session["logged_in"] = False

def handle_login_exception(e):
    return redirect("/login")

def get_recent_invalid_login_attempts():
    global recent_invalid_login_attempts
    global recent_invalid_login_time_marker

    # Reset count if it's been 5 minutes since first bad login
    if time.time() > recent_invalid_login_time_marker + 300:
        recent_invalid_login_attempts = 0

    return recent_invalid_login_attempts

def increase_recent_invalid_login_attempts():
    global recent_invalid_login_attempts
    global recent_invalid_login_time_marker

    # Mark time of first invalid login so we know when we would need to reset
    if recent_invalid_login_attempts == 0:
        recent_invalid_login_time_marker = time.time()

    recent_invalid_login_attempts += 1

def get_login_error_message():
    global login_error_message
    return login_error_message
