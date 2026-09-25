"""Entrypoint for the mocked UI dev container.

Imports the real Flask app (mynode.py) - every blueprint loads through the
mock shims on PYTHONPATH - seeds the module-global data caches the pages read,
registers the dev-only state-switcher blueprint, and runs Flask with debug
auto-reload. The real mynode.py is untouched: threads and dynamic-app
blueprints normally start in its __main__ block, which never runs here."""
import os
import threading
import time

import seed_fixture_fs

seed_fixture_fs.ensure()

from mynode import app, start_threads  # noqa: E402 - imports the real app through the shims

import utilities  # noqa: E402
from application_info import register_dynamic_app_flask_blueprints  # noqa: E402
import dev_blueprint  # noqa: E402

utilities.set_logger(app.logger)

# Populate the module-global caches so the very first page load is complete.
dev_blueprint.seed_runtime_data()

# Blueprints for dynamic apps under /usr/share/mynode_apps (normally done in
# mynode.py's __main__ block).
register_dynamic_app_flask_blueprints(app)

# Dev-only controls: /dev/* endpoints + floating overlay on every HTML page.
app.register_blueprint(dev_blueprint.mynode_dev)
app.after_request(dev_blueprint.inject_overlay)
if os.environ.get("DEV_AUTOLOGIN") == "1":
    app.before_request(dev_blueprint.autologin)


def _refresher():
    """Lightweight stand-in for the app's background threads: refreshes the
    mocked data every 30s (so values jitter and dev-panel knobs propagate)."""
    while True:
        time.sleep(30)
        try:
            dev_blueprint.seed_runtime_data(log_errors=True)
        except Exception as e:
            utilities.log_message("[dev refresher] {}".format(e))


if __name__ == "__main__":
    if os.environ.get("DEV_REAL_THREADS") == "1":
        # Run the app's real background threads (all bodies are mock-safe)
        start_threads()
    else:
        threading.Thread(target=_refresher, daemon=True).start()

    app.run(host="0.0.0.0", port=8000, debug=True)
