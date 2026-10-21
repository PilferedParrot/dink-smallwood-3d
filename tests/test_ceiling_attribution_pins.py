"""Every terrain-attributed ceiling frame is pinned at its attributed hash: pure data, no engine.

The merge of the terrain columns pinned 39 frames (attribution B) and missed screen 102
(attribution A, an earlier terrain commit), so 102 kept the pre-terrain hash. This ties each
committed attribution record to the manifest pin and to the baseline (a21af9d) it changed from.
"""
import json
import subprocess

from tools.ceiling_donors import ROOT

FIXTURES = ROOT / 'tests/fixtures/ceilings'
ATTRIBUTION_FILES = ['terrain-columns-attribution.json', 'terrain-columns-attribution-102.json']
# The tile-class unit (baseline 638cec6) re-pinned the frames it changed; it supersedes the 'after' pin of those screens above.
CLASS_FILE = 'terrain-class-attribution.json'


def _class_records():
    data = json.loads((FIXTURES / CLASS_FILE).read_text())
    assert data['different_frames'] == len(data['frames'])
    assert data['changed_pixels'] == sum(r['changed_pixels'] for r in data['frames'])
    assert data['outside_column_bounds'] == sum(r['outside_column_bounds'] for r in data['frames']) == 0
    return {r['screen']: r for r in data['frames']}


def _records():
    for name in ATTRIBUTION_FILES:
        data = json.loads((FIXTURES / name).read_text())
        assert data['different_frames'] == len(data['frames']), name
        # The file's totals must be the sum of its records (outside_column_bounds is only in the first file).
        assert data['changed_pixels'] == sum(r['changed_pixels'] for r in data['frames']), name
        assert data.get('outside_column_bounds', 0) == sum(r['outside_column_bounds'] for r in data['frames']), name
        for record in data['frames']:
            yield name, record


def test_every_attributed_frame_is_pinned_at_its_attributed_hash():
    manifest = json.loads((FIXTURES / 'manifest.json').read_text())['frames']
    records = list(_records())
    screens = [r['screen'] for _, r in records]
    assert len(screens) == len(set(screens)) == 40
    for name, record in records:
        assert record['outside_column_bounds'] == 0, (name, record['screen'])
        assert record['before_rgb_sha256'] != record['after_rgb_sha256']
        later = _class_records().get(record['screen'])
        expected = later['after_rgb_sha256'] if later else record['after_rgb_sha256']
        assert manifest['%d.png' % record['screen']]['rgb_sha256'] == expected, (name, record['screen'])


def test_attributed_frames_changed_from_the_integrated_baseline_and_no_others_changed():
    baseline = json.loads(subprocess.check_output(['git', 'show', 'a21af9d:tests/fixtures/ceilings/manifest.json'], cwd=ROOT))['frames']
    manifest = json.loads((FIXTURES / 'manifest.json').read_text())['frames']
    attributed = {r['screen'] for _, r in _records()}
    changed = {int(n.split('.')[0]) for n in manifest if manifest[n]['rgb_sha256'] != baseline[n]['rgb_sha256']}
    assert changed == attributed | set(_class_records()), sorted(changed ^ (attributed | set(_class_records())))
    for _, record in _records():
        assert baseline['%d.png' % record['screen']]['rgb_sha256'] == record['before_rgb_sha256'], record['screen']


def test_tile_class_frames_changed_from_the_0_3_3_pins_and_no_others():
    base = json.loads(subprocess.check_output(['git', 'show', '638cec6:tests/fixtures/ceilings/manifest.json'], cwd=ROOT))['frames']
    manifest = json.loads((FIXTURES / 'manifest.json').read_text())['frames']
    records = _class_records()
    changed = {int(n.split('.')[0]) for n in manifest if manifest[n]['rgb_sha256'] != base[n]['rgb_sha256']}
    assert changed == set(records), sorted(changed ^ set(records))
    for screen, record in records.items():
        key = '%d.png' % screen
        assert record['before_rgb_sha256'] == base[key]['rgb_sha256'], screen
        assert record['after_rgb_sha256'] == manifest[key]['rgb_sha256'], screen
        assert record['before_rgb_sha256'] != record['after_rgb_sha256']
        assert record['outside_column_bounds'] == 0 and record['negative_control_outside'] == 1, screen
