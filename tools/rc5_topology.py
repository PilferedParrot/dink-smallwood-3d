import argparse,hashlib,json,sys,collections
from pathlib import Path
import numpy as np
from scipy import ndimage
sys.path.insert(0,str(Path(__file__).resolve().parent))
from collision_map import tile_mask,rect_mask
from rc5_hardness_census import reachable_boundaries
root=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser(description='Compare RC4 baseline reachability with fitted RC5 walls and fir bodies. Static integer-pixel graph only.')
ap.add_argument('--baseline',type=Path,required=True)
ap.add_argument('--native',type=Path,required=True)
ap.add_argument('--out',type=Path,required=True)
ap.add_argument('--probes',type=Path)
ap.add_argument('--mask-out',type=Path,help='Optional compressed before/after collision and reachability masks for content/interaction audits')
args=ap.parse_args()
world=json.loads((root/'game/data/world.json').read_text());fp=json.loads((root/'game/data/footprints.json').read_text())['screens']
native=json.loads(args.native.read_text());walls=json.loads((root/'game/prototype/rc5_walls.json').read_text());firs=json.loads((root/'game/prototype/rc5_fir_collision.json').read_text());baseline=json.loads(args.baseline.read_text())
records={q['id']:q for q in firs['rectangles']}
rows=(max(map(int,world['screens']))+31)//32
base=np.zeros((rows*400,19200),bool);after=base.copy();wallraw=base.copy()
counts={};screens={}
for key,fixtures in baseline['screens'].items():
 n=int(key);oy=((n-1)//32)*400;ox=((n-1)%32)*600
 for y,a,b,_ in fixtures[0]['classification_runs']:base[oy+y,ox+a-20:ox+b-20]=True
 if key in walls['screens']:
  for y,a,b in walls['screens'][key]['floor_runs']:wallraw[oy+y,ox+a-20:ox+b-20]=True
# Sparse per-screen halo dilation instead of a 184M-pixel whole-world stencil.
yy,xx=np.mgrid[-5:6,-5:6]
struct=(np.maximum(np.maximum(-xx,xx-1),0)**2+np.maximum(np.maximum(-yy,yy-1),0)**2)<=16
for key,fixtures in baseline['screens'].items():
 n=int(key);oy=((n-1)//32)*400;ox=((n-1)%32)*600
 tile,_=tile_mask(world,n,fp.get(key,{}).get('revert',()),fp.get(key,{}).get('clear',()))
 if key in walls['screens']:
  for y,a,b in walls['screens'][key]['clear_tile_runs']:tile[y,a:b]=False
 selected=set(walls.get('screens',{}).get(key,{}).get('owner_indexes',[]))
 rects=[]
 for e,inv in zip(world['screens'][key]['sprites'],native['screens'][key],strict=True):
  if e.get('vision',0)!=0 or e.get('hard',1)!=0 or e.get('warp') is not None:continue
  if e['index'] in fp.get(key,{}).get('sprites',[]) or e['index'] in selected:continue
  rects.append(inv['hard_rect'])
 hard=tile|rect_mask(rects,4)
 for y,a,b in native['footprint_layers'][key]['0']:hard[y,a:b]=True
 y0=max(0,oy-6);x0=max(0,ox-6);y1=min(base.shape[0],oy+406);x1=min(base.shape[1],ox+606)
 halo=wallraw[y0:y1,x0:x1]
 if halo.any():hard[:,20:620] |= ndimage.binary_dilation(halo,structure=struct)[oy-y0:oy-y0+400,ox-x0:ox-x0+600]
 active=[e['rect_local_xyxy'] for e in firs['by_screen'].get(key,[]) if n in records[e['id']]['scene5x5_shown_centers']]
 hard|=rect_mask(active,4)
 after[oy:oy+400,ox:ox+600]=hard[:,20:620]
 beforelocal=base[oy:oy+400,ox:ox+600]
 counts[key]={'new_blocked_px':int((hard[:,20:620]&~beforelocal).sum()),'removed_blocked_px':int((beforelocal&~hard[:,20:620]).sum())}
 labels=np.where(hard,1,0).astype(np.int8);runs=[]
 for y,row in enumerate(labels):
  edges=np.r_[0,np.flatnonzero(np.diff(row))+1,len(row)]
  runs.extend([y,int(a),int(b),1] for a,b in zip(edges[:-1],edges[1:]) if row[a])
 screens[key]=[{'classification_runs':runs}]
probe_count=0
if args.probes:
 probes=json.loads(args.probes.read_text())
 mismatches=[]
 for key,points in probes['screens'].items():
  n=int(key);oy=((n-1)//32)*400;ox=((n-1)%32)*600
  for x,y,actual in points:
   predicted=bool(after[oy+int(y),ox+int(x)-20]);probe_count+=1
   if predicted!=actual:mismatches.append([n,x,y,predicted,actual])
 assert not mismatches, f'Native mask mismatch: {mismatches[:20]}'
 print('Native collision mask probes match',probe_count,flush=True)
print('constructed changed masks',flush=True)
reach=reachable_boundaries(world,screens,native)
# The reach helper annotates each fixture; build its exact reached free mask
# using the same graph instead of inferring reachability from a screen-level flag.
# Compare reachability counts per screen after removing newly occupied points.
for key in counts:
 old=baseline['screens'][key][0]['static_warp_reachable_free_px'];new=screens[key][0]['static_warp_reachable_free_px']
 counts[key]['before_reachable_free_px']=old;counts[key]['after_reachable_free_px']=new
# Rebuild baseline and after graphs per-pixel with each set's reached components.
# Seed plus warp closure here independently captures any detached surviving area.
def reached_mask(hard):
 free=np.zeros_like(hard)
 for key in baseline['screens']:
  n=int(key);oy=((n-1)//32)*400;ox=((n-1)%32)*600;free[oy:oy+400,ox:ox+600]=~hard[oy:oy+400,ox:ox+600]
 labels,num=ndimage.label(free)
 # Static warps can link through indoor rooms. Reuse native indoor component data.
 indoor={};tagmax=int(labels.max())+1
 for key,d in native['indoor_collision'].items():
  t,_=tile_mask(world,int(key),fp.get(key,{}).get('revert',()),fp.get(key,{}).get('clear',()))
  t|=rect_mask(d['hard_rects'],4)
  for y,a,b in d['footprint_runs']:t[y,a:b]=True
  f=~t;f[:,:20]=False;f[:,620:]=False;l,c=ndimage.label(f);l[l!=0]+=tagmax-1;tagmax+=c;indoor[key]=l
 def dest(n,x,y):
  if not(20<=x<620 and 0<=y<400):return 0
  if str(n) in indoor:return int(indoor[str(n)][int(y),int(x)])
  if str(n) not in baseline['screens']:return 0
  return int(labels[((n-1)//32)*400+int(y),((n-1)%32)*600+int(x)-20])
 edges=[]
 for w in native['static_warps']:
  n=w['screen'];a,b,c,d=w['trigger'];x0=max(20,int(np.ceil(a)));x1=min(620,int(np.ceil(c)));y0=max(0,int(np.ceil(b)));y1=min(400,int(np.ceil(d)))
  if x1<=x0 or y1<=y0:continue
  if str(n) in indoor:src=set(map(int,np.unique(indoor[str(n)][y0:y1,x0:x1])))
  elif str(n) in baseline['screens']:
   oy=((n-1)//32)*400;ox=((n-1)%32)*600-20;src=set(map(int,np.unique(labels[oy+y0:oy+y1,ox+x0:ox+x1])))
  else:continue
  src.discard(0);target=dest(w['target'],*w['destination'])
  if target:edges.append((src,target))
 tag=int(labels[((439-1)//32)*400+390,((439-1)%32)*600+323-20]);assert tag;tags={tag}
 change=True
 while change:
  change=False
  for src,target in edges:
   if tags.intersection(src) and target not in tags:tags.add(target);change=True
 return np.isin(labels,list(tags))
rb=reached_mask(base);print('base graph complete',flush=True)
ra=reached_mask(after);print('after graph complete',flush=True)
cut=rb&~after&~ra;added=rb&after&~base
if args.mask_out:
 args.mask_out.parent.mkdir(parents=True,exist_ok=True)
 np.savez_compressed(args.mask_out,before_hard=base,after_hard=after,before_reachable=rb,after_reachable=ra)
out={'schema':'rc5-topology-1','native_mask_probe_count':probe_count,'inputs_sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [args.baseline,args.native,root/'game/prototype/rc5_walls.json',root/'game/prototype/rc5_fir_collision.json']},'new_blocked_previously_reachable_px':int(added.sum()),'previously_reachable_surviving_px_cut_off':int(cut.sum()),'per_screen':counts,'after_reachability':{k:reach[k] for k in ('seed','method','reachable_screens','reachable_free_px','unverified_static_warps','not_connected_outdoor_screens','limits')},'cut_off_components':[]}
for key in counts:
 n=int(key);oy=((n-1)//32)*400;ox=((n-1)%32)*600
 counts[key]['new_blocked_reachable_px']=int(added[oy:oy+400,ox:ox+600].sum())
 local=cut[oy:oy+400,ox:ox+600];counts[key]['cut_off_surviving_px']=int(local.sum())
 if local.any():
  l,c=ndimage.label(local)
  for i,b in enumerate(ndimage.find_objects(l),1):out['cut_off_components'].append({'screen':n,'pixels':int((l==i).sum()),'bbox_xyxy':[b[1].start+20,b[0].start,b[1].stop+20,b[0].stop]})
args.out.parent.mkdir(parents=True,exist_ok=True)
args.out.write_text(json.dumps(out,separators=(',',':'))+'\n')
print('TOPOLOGY',out['new_blocked_previously_reachable_px'],out['previously_reachable_surviving_px_cut_off'],flush=True)
