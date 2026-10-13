"""Isolate native profiles and use a bounded software renderer for tests."""
from __future__ import annotations

import os
import shutil
from pathlib import Path
import pytest


def pytest_configure(config):
    config.addinivalue_line("markers",
        "local_evidence(reason): checks locally generated evidence absent from fresh checkouts and CI")


def pytest_sessionstart(session):
    if os.environ.get("DINK_REQUIRE_GODOT") != "1":
        return
    godot = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
        Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64")
    if not Path(godot).is_file() or not os.access(godot, os.X_OK):
        raise pytest.UsageError(f"DINK_REQUIRE_GODOT=1: executable Godot is missing: {godot}")
    if not shutil.which("xvfb-run"):
        raise pytest.UsageError("DINK_REQUIRE_GODOT=1: xvfb-run is missing")


@pytest.fixture(scope="session", autouse=True)
def isolated_native_profile(tmp_path_factory):
    # Individual fixtures can still override these directories for independent
    # saves. The session default also contains imports, exports and small probes
    # whose subprocess inherits the environment without a per-test override.
    profile = tmp_path_factory.mktemp("native-profile")
    with pytest.MonkeyPatch.context() as patch:
        for name, folder in (("XDG_DATA_HOME", "data"),
                             ("XDG_CONFIG_HOME", "config"),
                             ("XDG_CACHE_HOME", "cache")):
            patch.setenv(name, str(profile / folder))
        for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
            patch.setenv(name, "1")
        patch.setenv("LIBGL_ALWAYS_SOFTWARE", "1")
        patch.setenv("GALLIUM_DRIVER", "llvmpipe")
        patch.setenv("LP_NUM_THREADS", os.environ.get("LP_NUM_THREADS", "1"))
        yield
