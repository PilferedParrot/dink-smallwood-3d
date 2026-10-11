#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Choose reachable, crown-clear poses for the bounded forest picture fixture.

Reuse the final RC5 static reach masks; native checks separately query the real
game's hardness at each eye position. This is a scenario setup, not progression.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]

def spacing_figure(fit: dict, out: Path):
    """Source-art observation chart, preserving the bitmap below annotations."""
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",17)
    fig = Image.new("RGB",(1200,700),(24,27,25))
    draw = ImageDraw.Draw(fig)
    atlas = Image.open(ROOT / "game/assets/tiles/ts01.png").convert("RGB")
    strip = Image.open(ROOT / "game/assets/graphics/lands/Trees/tree-08.png").convert("RGB")
    atlas = atlas.crop((200,200,400,400)).resize((600,600),Image.Resampling.NEAREST)
    strip = strip.resize((600,285),Image.Resampling.NEAREST)
    fig.paste(atlas,(600,60)); fig.paste(strip,(0,60))
    draw.text((8,8),"tree08: exact top-row / periodic-edge apexes",font=font,fill="white")
    draw.text((608,8),"ts01: four foreground tips, +/-4px boxes",font=font,fill="white")
    source = fit["rule"]["spacing_source"]
    for i,(x,y) in enumerate(source["tree08_apex_xy"]):
        px,py=min(599,x*3),60+y*3
        draw.ellipse((px-5,py-5,px+5,py+5),outline="cyan",width=2)
        draw.text((max(3,px-26),py+10),f"{i}: {x:g},{y:g}",font=font,fill="cyan")
    for i,(x,y) in enumerate(source["atlas_foreground_apex_xy_approx"]):
        px,py=600+(x-200)*3,60+(y-200)*3
        draw.rectangle((px-12,py-12,px+12,py+12),outline="cyan",width=2)
        draw.text((px+15,py),str(i),font=font,fill="cyan")
    draw.text((8,380),f"Nearest source spacing: {fit['rule']['minimum_root_spacing_px']:.8f}px",font=font,fill="white")
    draw.text((8,410),"tree08 edge tips repeat at x=1/201.",font=font,fill="white")
    draw.text((8,440),"Atlas uncertainty cannot change the smaller spacing.",font=font,fill="white")
    draw.text((8,470),"No claim of recovered hidden tree depth.",font=font,fill="white")
    fig.save(out / "source-spacing.png")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fit", type=Path, default=ROOT / "game/prototype/rc5_forest_preview.json")
    parser.add_argument("--masks", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    fit = json.loads(args.fit.read_text())
    args.out.mkdir(parents=True, exist_ok=True)
    spacing_figure(fit,args.out)
    proof = []
    intentions = {
        144: [("west", (120,230), (245,230)), ("east", (470,230), (375,230)),
              ("south", (300,395), (300,260)), ("north", (305,5), (305,150))],
        375: [("west", (265,70), (385,80)), ("south", (445,240), (445,100)),
              ("east", (590,220), (510,110)), ("southwest", (275,215), (385,100))],
    }
    with np.load(args.masks) as masks:
        for n, poses in intentions.items():
            oy, ox = (n-1)//32*400, (n-1)%32*600
            free = masks["after_reachable"][oy:oy+400, ox:ox+600] & ~masks["after_hard"][oy:oy+400, ox:ox+600]
            yy, xx = np.where(free)
            interior = (xx >= 5) & (xx <= 594) & (yy >= 5) & (yy <= 394)
            xx, yy = xx[interior], yy[interior]
            rows = fit["screens"][str(n)]
            roots = rows["current_visible_roots"] + rows["added_roots"]
            clearance = np.full(len(xx), np.inf)
            for root in roots:
                x, y = root["foot_local_px"]
                # Source-foot coverage is not card placement or 3D volume.
                # A 20px safety margin also avoids the generic tree01 hotspot
                # discrepancy; native hardness is checked independently.
                radius = 47 * root["uniform_scale"] + 20
                clearance = np.minimum(clearance, np.hypot(xx-x, yy-y) - radius)
            valid = clearance > 0
            xx, yy, clearance = xx[valid], yy[valid], clearance[valid]
            views = []
            for name, desired, target in poses:
                dx, dy = desired
                tx, ty = target
                # Keep the requested viewing side of the target.
                side = (xx-tx)*(dx-tx) + (yy-ty)*(dy-ty) > 0
                indices = np.flatnonzero(side)
                if not len(indices): raise ValueError((n,name,"no clear reachable eye"))
                best = indices[np.argmin((xx[indices]-dx)**2+(yy[indices]-dy)**2)]
                x, y = int(xx[best]), int(yy[best])
                view = {"name":f"{n}-{name}", "x":x+20,"y":y,
                        "yaw":math.atan2(x-tx,y-ty),"pitch":-0.05}
                views.append(view)
                proof.append({"screen":n,"name":view["name"],"source_xy":[x+20,y],
                    "aim_local_xy":[tx,ty],"static_reachable":True,"static_hard":False,
                    "minimum_clearance_beyond_47px_scaled_radius_plus_20px":float(clearance[best])})
            views.append({"name":f"{n}-original","original":True})
            (args.out / f"{n}.json").write_text(json.dumps(views,indent=2)+"\n")
    (args.out / "proof.json").write_text(json.dumps({"poses":proof,
        "fit_sha256":hashlib.sha256(args.fit.read_bytes()).hexdigest(),
        "reach_masks_sha256":hashlib.sha256(args.masks.read_bytes()).hexdigest(),
        "limit":"Source-foot disc clearance is a conservative 2D proxy, not a reconstructed crown. Original-camera views have no player eye pose."},indent=2)+"\n")
    print(json.dumps(proof,indent=2))

if __name__ == "__main__": main()
