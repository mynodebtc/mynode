from flask import Blueprint, render_template, session, abort, Markup, request, redirect, send_from_directory, url_for, flash
from config import *
import pam
import os
import subprocess

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
    p = pam.pam()
    if password == None or p.authenticate("admin", password) == False:
        return False
    else:
        session["logged_in"] = True
        session.permanent = True
        return True

def logout():
    session["logged_in"] = False

def handle_login_exception(e):
    return redirect("/login")