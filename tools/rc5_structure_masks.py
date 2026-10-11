"""Independent integer-pixel masks for the compiled RC5 structure geometry.

Wall occupied cells are literal closed unit squares with a Euclidean four-pixel
band, including neighboring screens. Fir bands use the original square grow.
"""
import numpy as np
from scipy import ndimage
from collision_map import rect_mask


def structure_masks(screen, walls, firs):
    halo = np.zeros((410, 610), bool)
    col = (screen - 1) % 32
    for dz in range(-1, 2):
        for dx in range(-1, 2):
            if not 0 <= col + dx < 32:
                continue
            other = screen + dx + 32*dz
            for y, a, b in walls.get('screens', {}).get(str(other), {}).get('floor_runs', []):
                hy = dz*400 + y + 5
                x0 = max(0, dx*600 + a - 20 + 5)
                x1 = min(610, dx*600 + b - 20 + 5)
                if 0 <= hy < 410 and x0 < x1:
                    halo[hy, x0:x1] = True
    yy, xx = np.mgrid[-5:6, -5:6]
    stencil = (np.maximum(np.maximum(-xx,xx-1),0)**2 +
               np.maximum(np.maximum(-yy,yy-1),0)**2) <= 16
    wall = np.zeros((400,640),bool)
    wall[:,20:620] = ndimage.binary_dilation(halo,structure=stencil)[5:405,5:605]
    records = {q['id']:q for q in firs.get('rectangles',[])}
    active = [q['rect_local_xyxy'] for q in firs.get('by_screen',{}).get(str(screen),[])
              if screen in records[q['id']]['scene5x5_shown_centers']]
    fir = rect_mask(active,4)
    fir[:,:20]=False;fir[:,620:]=False
    return wall, fir
