"""Pick the Python that runs a tools/*.py reader from a test (shared by the tests that shell out to one).

CI installs requirements-dev.txt into the interpreter running pytest, and the runner's /usr/bin/python3 has none of it;
this machine is the other way round, its numpy, scipy and PIL being apt packages of /usr/bin/python3. So take the first
of the two that can import what the tool needs, and fail by name when neither can: a test that skipped here is how the
bridge-rails check went unrun on CI.
"""
import subprocess
import sys
from pathlib import Path

SYSTEM_PYTHON = "/usr/bin/python3"


def python_with(modules, tool):
    """An interpreter that can import `modules` (a comma-separated string, as `import` takes them) for tools/<tool>:
    the one running pytest, else the system one."""
    for py in (sys.executable, SYSTEM_PYTHON):
        if Path(py).is_file() and subprocess.run([py, "-c", "import " + modules], capture_output=True).returncode == 0:
            return py
    raise AssertionError("no python with %s for %s: pip install -r requirements-dev.txt" % (modules, tool))
