#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Comb-stripe measure for rendered wall faces: horizontal over vertical luma-gradient energy in a pixel box.

A plain rock face is isotropic (ratio about 1; mid-99 b1 reads 0.96). Alternating thin light/dark columns, the picket/comb
class from a ragged rim's steps, push it to 2.4-2.9 (100-t0 on the pre-fix frames). Gate: ratio < 1.5 on each face box.
Usage: face_comb.py IMAGE X0 Y0 X1 Y1
"""
import sys
import numpy as np
from PIL import Image
def metric(path, box):
    im=np.asarray(Image.open(path).convert('L')).astype(float)
    x0,y0,x1,y1=box; r=im[y0:y1,x0:x1]
    gx=np.abs(np.diff(r,axis=1)).mean(); gy=np.abs(np.diff(r,axis=0)).mean()
    return gx,gy,gx/max(gy,1e-6)
if __name__=='__main__':
    p=sys.argv[1]; box=tuple(int(v) for v in sys.argv[2:6]); print('gx %.2f gy %.2f ratio %.2f'%metric(p,box))
