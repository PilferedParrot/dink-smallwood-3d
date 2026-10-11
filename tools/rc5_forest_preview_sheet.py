#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Assemble matching packed forest views and an observation-free artifact ledger."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("directory",type=Path)
    args=p.parse_args()
    root=args.directory
    font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",17)
    ledger=["# Forest preview artifact ledger", "", "Packed vision0 editor-layer scenario; startup scripts and campaign progression skipped. Matching cameras and source scenes in all columns. No HUD. No verdicts in this ledger.", "", "Columns: baseline RC5; A whole firs over original tile art; B the same firs over source grass donors. Firs have no added colliders. Original views use the existing orthographic source-camera harness, not the original 2D game.", "", "Eye pose qualification: `views/proof.json`, independently checked against native hardness in `gates.json`.", ""]
    sheets=[]
    for screen in (144,375):
        views=json.loads((root/"views"/f"{screen}.json").read_text())
        sheet=Image.new("RGB",(1920,40+len(views)*412),(24,27,25))
        draw=ImageDraw.Draw(sheet)
        for col,label in enumerate(("Baseline RC5","A: whole firs / original ground","B: whole firs / grass donor")):
            draw.text((col*640+8,8),label,font=font,fill="white")
        for row,view in enumerate(views):
            name=view["name"]
            label=f"Screen {screen} / original camera" if view.get("original") else f"Screen {screen} / {name.split('-',1)[1]} / eye ({view['x']}, {view['y']})"
            for col,phase in enumerate(("before","fir","floor")):
                path=root/phase/str(screen)/f"{name}.png"
                image=Image.open(path).convert("RGB")
                image.thumbnail((640,380),Image.Resampling.LANCZOS)
                sheet.paste(image,(col*640+(640-image.width)//2,40+row*412+28))
                draw.text((col*640+8,40+row*412+5),label,font=font,fill="white")
                ledger.append(f"- `{path.relative_to(root)}`: {label}; column {phase}; SHA256 `{hashlib.sha256(path.read_bytes()).hexdigest()}`.")
        out=root/f"forest-{screen}.jpg"
        sheet.save(out,quality=93)
        sheets.append(sheet)
        ledger += ["",f"Sheet: `{out.name}`.",""]
    combined=Image.new("RGB",(1920,sum(s.height for s in sheets)),(24,27,25))
    top=0
    for sheet in sheets:
        combined.paste(sheet,(0,top));top+=sheet.height
    combined.save(root/"forest-sheet.jpg",quality=93)
    (root/"ARTIFACT_LEDGER.md").write_text("\n".join(ledger)+"\n")
    print(root/"forest-sheet.jpg")

if __name__=="__main__":main()
