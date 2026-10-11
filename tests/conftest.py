"""Keep every native test subprocess out of the player's Godot profile."""
from __future__ import annotations

import pytest


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
        yield
