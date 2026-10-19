"""A signed reconstruction filter must not punch holes in permitted support."""

import numpy as np
from PIL import Image
import pytest
from tools.building_render_gate import lanczos_support


def test_lanczos_support_keeps_the_full_footprint_even_when_white_filtering_cancels(tmp_path):
    pixels = np.zeros((40, 40), np.uint8)
    pixels[20, 20] = 255
    path = tmp_path / "native.png"
    Image.fromarray(pixels).save(path)
    actual = np.asarray(lanczos_support(path, (20, 20))) != 0
    # At 2:1 reduction, the impulse lies in six consecutive Lanczos3 windows
    # on each axis. Negative lobes can make a filtered white mask lose support.
    expected = np.zeros((20, 20), bool)
    expected[7:13, 7:13] = True
    assert np.array_equal(actual, expected)
    filtered = np.asarray(Image.fromarray(pixels).resize((20, 20), Image.Resampling.LANCZOS)) != 0
    assert np.count_nonzero(filtered) < np.count_nonzero(actual)
    assert np.any(actual & ~filtered)


def test_native_support_rejects_coloured_scenery_instead_of_blessing_its_pixels(tmp_path):
    pixels = np.zeros((8, 8, 3), np.uint8)
    pixels[4, 4] = [255, 0, 0]
    path = tmp_path / "invalid.png"
    Image.fromarray(pixels).save(path)
    with pytest.raises(ValueError, match="coloured scenery"):
        lanczos_support(path, (4, 4))
