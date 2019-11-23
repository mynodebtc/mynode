from flask import Blueprint, render_template
from settings import read_ui_settings
from user_management import check_logged_in

mynode_whirlpool_cli = Blueprint('mynode_whirlpool_cli',__name__)

### Page functions
@mynode_whirlpool_cli.route("/whirlpool-cli")
def bitcoincli():
    check_logged_in()

    # Load page
    templateData = {
        "title": "myNode Whirlpool CLI",
        "ui_settings": read_ui_settings()
    }
    return render_template('whirlpool_cli.html', **templateData)