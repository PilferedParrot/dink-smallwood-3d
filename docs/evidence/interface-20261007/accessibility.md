# Accessibility review: Dink Smallwood3D (2026-10-07)
Reviewer: GPT-6.1 Sol, self-reported. Frames: 9. Lens: accessibility.

## Top findings (most severe first, at most 7)
| # | Severity | Frame | What a player sees | Why it matters | Confidence |
|---|---|---|---|---|---|
| 1 | blocks play | adventure.png; map-feedback.png; pause hint, (916,616)–(1008,635) | “Esc Pause” sits over the brightly lit hand. The ruler measures 2.96:1 and 2.94:1 respectively; enlarged pixels show a lower/right shadow but exposed pale letter edges against the hand. | A necessary control instruction is below 3:1, blocking its reliable reading for low-vision players; standard text needs 4.5:1. | High |
| 2 | hurts first impression | adventure.png; map-feedback.png; HUD labels, (202,699)–(595,790) | Textured Attack, Defense and Magic lettering has local contrast around 4.2–4.4:1. Adventure’s Life label measures 4.25:1. | These identify gameplay statistics and fall below 4.5:1. Their decorative treatment does not make their information decorative. | Medium: patterned lettering makes exact foreground classification sensitive; manual Attack/Defense/Magic boxes reproduce the shortfall. |
| 3 | hurts first impression | adventure.png; map-feedback.png; status text at (421,654)–(787,673), coins value (639,767)–(652,783); equipment.png E marker (715,292)–(725,308); title.png bottom Arrows; pause.png/equipment.png/journal-back.png bottom Esc Resume | Several small rendered labels measure 12px ink height (16.2px normalized to 1080p): Bow, level/EXP, coin count and E marker. Some prompts measure 13px (17.6px normalized). | Below the 18px PC reference minimum; status and input information are hardest to read precisely where the larger menu typography is otherwise clear. | Medium: these exact strings have few or no descenders, so their ink height can underestimate the full font body. Confirm font ascender/descender bounds before treating borderline 17.6px cases as definitive failures. |
| 4 | polish | title.png; development version, (749,584)–(955,602) | “Development release 0.3.0” measures 16.2px body height at 1080p, despite ample contrast (17.66:1). | Small informational text is below the PC size reference; this line is not needed to play. | Medium: ruler excludes faint antialiasing pixels. |

## All findings
| # | Severity | Frame | What a player sees | Why it matters | Confidence |
|---|---|---|---|---|---|
| 1 | blocks play | adventure.png; map-feedback.png; (916,616)–(1008,635) | Esc Pause contrasts 2.96:1 / 2.94:1 against the hand; one-sided shadow leaves exposed letter edges. | Necessary instruction below 3:1 for low vision, below 4.5:1 standard text requirement. | High |
| 2 | hurts first impression | adventure.png; map-feedback.png; HUD, (202,699)–(595,790) | Attack/Defense/Magic contrast about 4.2–4.4:1; Life 4.25:1 in adventure. | Required statistic labels below 4.5:1. | Medium: textured glyph measurement, reproduced in manual boxes. |
| 3 | hurts first impression | adventure.png/map-feedback.png small HUD text; equipment.png E; title.png Arrows; pause.png/equipment.png/journal-back.png Esc Resume | 12–13px rendered ink height, normalized to 16.2–17.6px at 1080p. | Below 18px PC reference; exact font body needs confirmation for strings without descenders. | Medium |
| 4 | polish | title.png; (749,584)–(955,602) | Version line measures 16.2px at 1080p. | Below size reference, but not necessary to play. | Medium |

## Per-frame notes

**title.png:** Large original-style logo draws attention before the right-hand menu. The selected Begin adventure button has a thick bright outline; labels and keyboard instructions are plainly distinguishable on dark backgrounds. Checked title, buttons, directions, attribution and footer. Findings 3–4 cover small text. The OCR “Q” box on the logo is visibly part of the Dink logotype and exempt, not an unreadable instruction.

**dialogue.png:** Mother and her request sit above one broad Continue button. Speaker, sentence and action are readable; measured dialogue body is 33.8px at 1080p and Continue contrast is 8.65:1. Checked speaker distinction, focus, text backdrop and bottom instruction; no additional finding in this frame.

**adventure.png:** Bow and hand dominate the right, Mother the centre-left, and an ornate status strip the bottom. Checked all text, crosshair, status categories and values. Findings 1–3 apply. The reticle has approximately 3.29:1 against this wall (sample saved in ruler directory), meeting the 3:1 non-text reference in this frame only. Health also has a numeric 10/10 cue, so red alone is not its only indicator. The unreadable OCR box (517,619,23,11) sits in the gap after “Mouse Look” over floor texture; pixels show no missing label there.

**equipment.png:** A parchment inventory board contains fist and bow icons; a thick pale frame selects the fist while a letter E marks the bow equipped. Checked focus versus equipped state, instructions, slot content, headers and exit button. The state has a letter cue, not colour alone. E contrast measures 5.69:1 but its 16.2px normalized ink height joins finding 3. OCR boxes at (669,324,15,13) and (541,231,23,22) cover bow artwork and board decoration; neither contains text. Large decorative headers remain readable in their annotated boxes.

**pause.png:** A tall list of clearly separated actions, with bright focus around Return to adventure. Checked every label, visible action ordering and footer. Labels measure at least 21.6px at 1080p and selected label contrast 8.65:1. Finding 3 includes the small Esc Resume footer.

**settings.png:** Readable keyboard/controller mappings occupy the upper half, with labelled audio and text sliders beneath and a visible scrollbar. Checked controller evidence, text scaling evidence, labels and master-volume focus. The OCR-unreadable box (210,195,798,21) actually reads “Talk: E / A … Equipment: I / Back” in the pixels; it measures 24.3px and 17.66:1, so recognition failure alone is rejected. Text size 100% is observable; maximum scaling, remapping, subtitle options, contrast/colour modes and reduced flashing are not observable below this scroll position. No absence finding is inferred.

**journal.png:** Large heading and conversation transcript with a wide focused return button. Checked all three conversation entries, heading, location, button and footer; no additional finding. Conversation text provides a readable textual record, though no timing or audio equivalence can be assessed.

**journal-back.png:** The paused-action list appears again with Return to adventure focused. Checked labels, focus and footer as in pause.png. Finding 3 recurs; this still does not establish focus-restoration behaviour during actual input.

**map-feedback.png:** A bright framed message explicitly says the map is not yet owned. Its measured contrast is 13.11:1 and normalized body height 28.4px. Checked message, HUD and control prompts; findings 1–3 recur. The OCR box (523,639,69,15) is visibly Mother’s hem/floor texture, not text. Camera/background agreement with adventure.png does not provide a useful changed camera viewpoint for parallax or solidity assessment.

Measurements used the existing measure_text.py and measure_box.py kit under nice 10 with single-thread environment settings. Source frames are native 1280×800 exports; heights are normalized by 1080/800 = 1.35, not treated as native 1080p pixels. Annotated outputs and JSON are in accessibility-ruler/. Automated severities were reviewed against actual pixels and required-text importance; a tool pass does not certify accessibility. Only the nine assigned frames inform this review.

Reference thresholds: [XAG 101 text display](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/101) specifies PC minimum body height of 18px at 1080p; [XAG 102 contrast](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/102) specifies 4.5:1 standard-text contrast against the least favourable backdrop; [WCAG 2.2 non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html) provides the 3:1 meaningful-component reference.

## What this lens is blind to
Still frames cannot establish input operation, focus movement, maximum text scaling, sound/subtitle equivalence, flashing, motion sensitivity or unseen settings. Software-GL/Xvfb UI captures do not certify target-GPU rendering or world/player experience.
