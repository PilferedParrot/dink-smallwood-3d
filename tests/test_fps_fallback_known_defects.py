"""Visible issue report for source forms that still use measured legacy bodies."""
import json
import math
from pathlib import Path

import pytest

FIXTURE = Path(__file__).parent / "fixtures/fallback-hitbody-baseline.json"
RECORDS = [r for r in json.loads(FIXTURE.read_text())["records"]
           if r["treatment"] == "unchanged-followup"]


@pytest.mark.parametrize("record", RECORDS,
                         ids=lambda r: f'{r["screen"]}:{r["editor"]}:{int(r["vision"])}')
def test_unresolved_fallback_source_form(record):
    defect = record.get("known_defect", {})
    assert defect.get("reason"), "Unresolved source form needs an explicit reason"
    offsets = defect.get("body_edge_offsets_px", {})
    assert set(offsets) == {"west", "north", "east", "south"}
    assert all(math.isfinite(float(v)) for v in offsets.values())
    # Native class census independently remeasures these offsets. Xfail here
    # is a visible issue report, not proof that the defect has been corrected.
    pytest.xfail(f'EDITOR-STATIC unresolved: {defect["reason"]}; '
                 f'south={offsets["south"]:+.3f}px, north={offsets["north"]:+.3f}px')
