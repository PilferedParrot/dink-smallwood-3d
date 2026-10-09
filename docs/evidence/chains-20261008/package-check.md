# Local exported pack verification, 2026-10-08

Linux `--export-pack` produced a76MiB local PCK; no release or publish.
Prototype JSON export filters explicitly include the fitted chain profile,
bridge atlas and existing props/fences. From an empty working directory,
headless Godot with only `--main-pack` found all four files and constructed
screens80and448 with no script errors (`PACKAGE PASS`). The probe reports
resource/RID leak warnings on shutdown; it does not certify lifecycle cleanup.

Software/Xvfb rendering through that packed root captured all seven chain
views plus hidden controls. All14 PNGs are pixel-identical to the reviewed
source final frames, recorded in package-render.json. No loose game source
root or player's profile was used; bwrap/private XDG/Dummy audio were used.

PCK and raw probe logs remain locally in `tmp/row8/package-check/`; only
readable verification/equality results are in the evidence commit. This is
Linux PCK data/runtime verification, not a Windows executable validation.
