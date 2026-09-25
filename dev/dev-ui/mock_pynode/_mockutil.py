"""Support code for the mock shim layer.

How the shim works
------------------
This directory sits FIRST on PYTHONPATH, before the real /var/www/mynode and
/var/pynode directories. When the real app does `import bitcoin_info` (or
`from bitcoin_info import *`), python finds the mock module here instead.

Each mock module follows the same three-step pattern:

    _real = load_real("bitcoin_info")   # exec the real file under an alias
    def fake(...): ...
    _real.some_function = fake          # patch INTO the real namespace
    export(globals(), _real)            # re-export the full patched surface

Patching into the real module namespace (instead of just defining same-named
functions in the mock) is essential: real function bodies resolve names
through their own module globals, and several consumers copy function objects
at import time via `from X import *`. Patching before export covers both.

While the real file is being exec'd, its own imports (e.g. lightning_info's
`from bitcoin_info import *`) resolve through sys.path and therefore pick up
the sibling mocks - so there is exactly one (patched) namespace per module.
"""
import copy
import importlib.util
import json
import os
import sys

REAL_SEARCH_PATHS = ["/var/pynode", "/var/www/mynode"]
FIXTURES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures")
MOCK_STATE_DIR = "/tmp/mock_state"

REAL_ALIAS_SUFFIX = "__real"


def load_real(name):
    """Exec the real module file under the alias '<name>__real' and return it."""
    alias = name + REAL_ALIAS_SUFFIX
    if alias in sys.modules:
        return sys.modules[alias]
    for search_path in REAL_SEARCH_PATHS:
        file_path = os.path.join(search_path, name + ".py")
        if os.path.isfile(file_path):
            spec = importlib.util.spec_from_file_location(alias, file_path)
            module = importlib.util.module_from_spec(spec)
            sys.modules[alias] = module
            try:
                spec.loader.exec_module(module)
            except Exception:
                del sys.modules[alias]
                raise
            return module
    raise ImportError("mock shim: real module '{}' not found in {}".format(name, REAL_SEARCH_PATHS))


def real(name):
    """Return the already-loaded real module object (for dev endpoints that
    need to poke module-level globals)."""
    return sys.modules[name + REAL_ALIAS_SUFFIX]


def export(mock_globals, real_module):
    """Copy the real module's (patched) namespace into the mock module so both
    `import X` and `from X import *` see the complete surface."""
    for key, value in vars(real_module).items():
        if key.startswith("__"):
            continue
        mock_globals[key] = value


_fixture_cache = {}


def fixture(name):
    """Load fixtures/<name> as JSON. Returns a deep copy so callers can mutate.
    Reloads automatically when the file changes on disk (live-editable)."""
    path = os.path.join(FIXTURES_DIR, name)
    mtime = os.path.getmtime(path)
    cached = _fixture_cache.get(name)
    if cached is None or cached[0] != mtime:
        with open(path) as f:
            _fixture_cache[name] = (mtime, json.load(f))
        cached = _fixture_cache[name]
    return copy.deepcopy(cached[1])


def get_knob(name, default=None):
    """Read a dev-panel knob from /tmp/mock_state/<name>.json."""
    try:
        with open(os.path.join(MOCK_STATE_DIR, name + ".json")) as f:
            return json.load(f)
    except Exception:
        return dict(default or {})


def set_knob(name, data):
    os.makedirs(MOCK_STATE_DIR, exist_ok=True)
    with open(os.path.join(MOCK_STATE_DIR, name + ".json"), "w") as f:
        json.dump(data, f)
