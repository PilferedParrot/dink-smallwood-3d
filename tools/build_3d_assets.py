"""Build the Dink Smallwood 3D asset library.

Run with: blender --background --python tools/build_3d_assets.py
The script deliberately uses only Blender's Python API and is deterministic.
Assets use Godot's coordinate convention: Y up, facing -Z, feet/base at Y=0.
"""
import json, math, os, random, sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game/assets/models"
ART = ROOT / "art"
random.seed(17)

COLORS = {
    "wood": (0.30, 0.12, 0.045, 1), "wood_light": (0.58, 0.29, 0.09, 1),
    "bark": (0.18, 0.07, 0.025, 1), "leaf": (0.12, 0.34, 0.08, 1),
    "leaf_dark": (0.045, 0.16, 0.035, 1), "plaster": (0.67, 0.42, 0.20, 1),
    "roof": (0.35, 0.08, 0.045, 1), "stone": (0.34, 0.34, 0.30, 1),
    "stone_light": (0.55, 0.52, 0.42, 1), "iron": (0.08, 0.09, 0.10, 1),
    "skin": (0.78, 0.45, 0.27, 1), "cloth": (0.16, 0.24, 0.50, 1),
    "red": (0.62, 0.075, 0.035, 1), "gold": (0.9, 0.55, 0.09, 1),
    "purple": (0.34, 0.10, 0.50, 1), "thatch": (0.88, 0.56, 0.12, 1), "slime": (0.18, 0.70, 0.22, 1),
    "water": (0.06, 0.35, 0.65, 1), "white": (0.84, 0.80, 0.64, 1),
}
MATS = {}

def mat(name, color, rough=0.82, metallic=0.0):
    m = bpy.data.materials.new(name); m.diffuse_color = color
    m.use_nodes = True; bs = m.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value = color; bs.inputs["Roughness"].default_value = rough
    bs.inputs["Metallic"].default_value = metallic
    return m

def make_materials():
    for n, c in COLORS.items(): MATS[n] = mat("Dink_" + n, c, 0.72 if n in ("iron", "water") else 0.88, 0.35 if n == "iron" else 0)
    # Small hand-authored procedural maps give the low-poly pieces readable surface detail.
    ART.mkdir(exist_ok=True)
    for n in ("wood", "plaster", "stone", "leaf", "roof", "thatch"):
        img = bpy.data.images.new("tex_" + n, 64, 64)
        base = COLORS[n][:3]; px = []
        for y in range(64):
            for x in range(64):
                noise = (((x * 37 + y * 17 + (x*y) * 3) % 29) - 14) / 255.0
                # Grain runs lengthwise, stone is coursed, and roof is visibly shingled.
                if n == "wood": noise += (.09 if (x + int(4 * math.sin(y*.35))) % 18 in (0, 1) else -.025)
                elif n == "stone": noise += (-.14 if y % 16 in (0, 1) or (x + (y//16 % 2)*8) % 24 in (0, 1) else .025)
                elif n == "roof": noise += (.12 if y % 12 in (0, 1, 2) else -.035)
                elif n == "thatch": noise += (.12 if (x + int(2*math.sin(y*.45))) % 7 in (0, 1) else -.025)
                elif n == "plaster": noise += .025 * math.sin(x*.72) * math.sin(y*.41)
                px.extend((max(0, min(1, base[0]+noise)), max(0, min(1, base[1]+noise)), max(0, min(1, base[2]+noise)), 1))
        img.pixels = px; img.filepath_raw = str(ART / (n + "_procedural.png")); img.file_format = "PNG"; img.save()
        nodes=MATS[n].node_tree.nodes; links=MATS[n].node_tree.links
        tex = nodes.new("ShaderNodeTexImage"); tex.image = img
        coord=nodes.new("ShaderNodeTexCoord"); mapping=nodes.new("ShaderNodeMapping")
        # Repeat architectural maps instead of stretching a single 64px sample over a wall.
        if n == "stone": mapping.inputs['Scale'].default_value=(7.0, 4.0, 1.0)
        elif n in ("roof", "thatch"): mapping.inputs['Scale'].default_value=(6.0, 4.0, 1.0)
        else: mapping.inputs['Scale'].default_value=(3.0, 3.0, 1.0)
        links.new(coord.outputs['UV'], mapping.inputs['Vector']); links.new(mapping.outputs['Vector'], tex.inputs['Vector'])
        bs = MATS[n].node_tree.nodes.get("Principled BSDF"); MATS[n].node_tree.links.new(tex.outputs["Color"], bs.inputs["Base Color"])

def set_mat(o, material):
    if material: o.data.materials.append(MATS[material] if isinstance(material, str) else material)
    return o

def smooth(o, bevel=0.0):
    if hasattr(o.data, "polygons"):
        for p in o.data.polygons: p.use_smooth = True
    if bevel:
        mod=o.modifiers.new("Rounded edges", "BEVEL"); mod.width=bevel; mod.segments=2
    return o

def apply_bevels(objs=None):
    """Bake bevels before static joins so the exported silhouette keeps its detail."""
    for o in (objs or list(bpy.context.scene.objects)):
        if o.type != 'MESH': continue
        bpy.context.view_layer.objects.active = o
        for mod in list(o.modifiers):
            if mod.type == 'BEVEL': bpy.ops.object.modifier_apply(modifier=mod.name)

def cube(n, loc, scale, material, bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(location=loc); o=bpy.context.object; o.name=n; o.scale=(scale[0]/2,scale[1]/2,scale[2]/2); bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    set_mat(o,material)
    # Architectural planes remain flat; only their rounded bevel carries a highlight.
    for p in o.data.polygons: p.use_smooth=False
    if bevel:
        mod=o.modifiers.new("Rounded edges", "BEVEL"); mod.width=bevel; mod.segments=2
        mod.harden_normals=True
    return o

def cyl(n, loc, radius, depth, material, verts=10, rot=None):
    # Authored in the game's Y-up convention; Blender primitives are Z-up.
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot or (math.pi/2,0,0)); o=bpy.context.object; o.name=n; return smooth(set_mat(o,material), min(radius*.16,.08))

def sphere(n, loc, scale, material):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=loc); o=bpy.context.object; o.name=n; o.scale=scale; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True); return smooth(set_mat(o,material))

def cone(n, loc, r1, r2, depth, material, verts=10):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=(-math.pi/2,0,0)); o=bpy.context.object; o.name=n; return smooth(set_mat(o,material), .03)

def torus(n, loc, major, minor, material, rot=(0,0,0)):
    if rot == (0,0,0): rot=(math.pi/2,0,0)
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=12, minor_segments=6, location=loc, rotation=rot); o=bpy.context.object; o.name=n; return set_mat(o,material)

def beam_between(n, a, b, radius, material):
    a,b=Vector(a),Vector(b); d=b-a; mid=(a+b)/2
    # Make this primitive unrotated first, then put its native local Z along the authored vector.
    # This avoids composing the Y-up cylinder factory rotation with the arbitrary beam rotation.
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=radius, depth=d.length, location=mid)
    o=bpy.context.object; o.name=n; set_mat(o, material); smooth(o, min(radius*.16,.08))
    o.rotation_mode='QUATERNION'; o.rotation_quaternion=Vector((0,0,1)).rotation_difference(d.normalized()); return o

def prism(n, verts, faces, material, bevel=0.0):
    mesh=bpy.data.meshes.new(n + "_mesh"); mesh.from_pydata(verts, [], faces); mesh.materials.append(MATS[material])
    # Explicit UVs ensure custom gables export their thatch/shingle maps to GLB.
    uv=mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for loop_i in poly.loop_indices:
            co=mesh.vertices[mesh.loops[loop_i].vertex_index].co
            uv.data[loop_i].uv=(co.x*.35, (co.y+co.z)*.35)
    o=bpy.data.objects.new(n, mesh); bpy.context.collection.objects.link(o)
    for p in mesh.polygons: p.use_smooth=False
    if bevel:
        mod=o.modifiers.new("Rounded edges", "BEVEL"); mod.width=bevel; mod.segments=2; mod.harden_normals=True
    return o

def reset():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)

def foliage(name, base=(0,0,0), dead=False, pine=False):
    x,y,z=base; cyl(name+"_trunk",(x,y+1.9,z),.34,3.8,"bark",8)
    if dead:
        for i, (dx, dz) in enumerate(((-1.5,-.4),(1.55,.2),(-1.1,.65),(1.15,-.72),(0,1.1))):
            beam_between(name+"_branch_%02d"%i,(x,y+2.0+i*.38,z),(x+dx,y+3.2+i*.36,z+dz),.13,"bark")
        return
    if pine:
        for i in range(4):
            cone(name+"_crown_%02d"%i,(x,y+3.0+i*.60,z),1.2-i*.2,.05,2.25,"leaf_dark" if i%2 else "leaf",10)
        return
    # Oak: a spreading crown, explicit limb structure, and a roughly five metre canopy.
    branches=((1.55,.2,2.65),(-1.6,-.35,2.8),(.8,1.35,3.25),(-.75,-1.25,3.35),(0,.2,3.65))
    for i,(dx,dz,h) in enumerate(branches): beam_between(name+"_branch_%02d"%i,(x,y+2.25,z),(x+dx*.55,y+h-.25,z+dz*.55),.16,"bark")
    crowns=((0,4.15,0,1.65),(-1.28,3.85,-.25,1.28),(1.3,3.9,.2,1.32),(-.55,4.75,.85,1.18),(.72,4.68,-.8,1.12),(0,5.25,.05,1.08))
    for i,(dx,h,dz,r) in enumerate(crowns):
        sphere(name+"_crown_%02d"%i,(x+dx,y+h,z+dz),(r, .85 if i < 3 else .78, r*.88),"leaf_dark" if i%2 else "leaf")
    return

def cottage(name):
    # Home/home-01: squat, dry-stone walls below a generous golden thatched gable.
    cube(name+"_stone_walls",(0,1.5,.12),(5.5,3,4.45),"stone",.10)
    # Front is -Z. A real roof is two sloped planes with triangular gable ends.
    cube(name+"_front_door",(0,1.0,-2.18),(1.15,2.0,.14),"wood",.03)
    cube(name+"_door_frame_top",(0,2.06,-2.28),(1.48,.16,.16),"wood_light")
    for x in (-.67,.67): cube(name+"_door_frame",(x,1.06,-2.28),(.15,2.05,.16),"wood_light")
    for x in (-2.0,2.0):
        cube(name+"_window_"+str(x),(x,1.45,-2.27),(1.0,.92,.13),"iron",.02)
        cube(name+"_window_cross_v"+str(x),(x,1.45,-2.36),(.09,1.0,.10),"wood_light")
        cube(name+"_window_cross_h"+str(x),(x,1.45,-2.36),(1.06,.09,.10),"wood_light")
    cube(name+"_stone_lintel",(0,2.20,-2.27),(1.65,.24,.19),"stone")
    # ridge runs X; eaves lie at z +/- 2.55 and peak y=5.3
    verts=[(-3.05,3.02,-2.55),(3.05,3.02,-2.55),(3.05,5.32,0),(-3.05,5.32,0),(-3.05,3.02,2.55),(3.05,3.02,2.55)]
    prism(name+"_thatched_gable_roof",verts,[(0,1,2,3),(3,2,5,4),(0,3,4),(1,5,2),(0,4,5,1)],"thatch",.025)
    # Dense overlapping thatch courses follow each roof slope and give its silhouette a soft edge.
    for side in (-1,1):
        for row in range(6):
            z=side*(2.32-row*.38); yy=3.22+row*.38
            sh=cube(name+"_thatch_course_%s_%02d"%("front" if side < 0 else "back",row),(0,yy,z),(6.18,.09,.60),"thatch",.012)
            sh.rotation_euler[0]=side*math.atan2(2.3,2.55)

def inn(name):
    """Outinn-inspired timber-framed roadside inn: gray stone, dark shingles, broad gable."""
    cube(name+"_stone_ground_floor",(0,1.12,.15),(6.6,2.24,4.8),"stone",.10)
    # Black timber frame is deliberately proud of the masonry/plaster facade.
    for x in (-2.95,-1.45,1.45,2.95): cube(name+"_frame_post_"+str(x),(x,2.15,-2.32),(.18,4.25,.18),"wood",.025)
    for y in (1.15,2.28,3.38): cube(name+"_frame_rail_"+str(y),(0,y,-2.32),(6.28,.17,.18),"wood",.025)
    for x in (-2.18,-.72,.72,2.18): beam_between(name+"_brace_"+str(x),(x-.54,2.35,-2.42),(x+.54,3.22,-2.42),.07,"wood")
    cube(name+"_front_door",(0,.92,-2.42),(1.16,1.84,.14),"wood_light",.025)
    for x in (-1.75,1.75):
        cube(name+"_window_"+str(x),(x,1.45,-2.41),(1.02,.78,.12),"iron",.015)
        cube(name+"_window_cross_"+str(x),(x,1.45,-2.49),(1.08,.08,.09),"wood_light",.01)
        cube(name+"_window_crossv_"+str(x),(x,1.45,-2.49),(.08,.84,.09),"wood_light",.01)
    verts=[(-3.65,3.35,-2.72),(3.65,3.35,-2.72),(3.65,5.75,0),(-3.65,5.75,0),(-3.65,3.35,2.72),(3.65,3.35,2.72)]
    prism(name+"_shingle_gable",verts,[(0,1,2,3),(3,2,5,4),(0,3,4),(1,5,2),(0,4,5,1)],"roof",.025)
    for side in (-1,1):
        for row in range(6):
            z=side*(2.5-row*.41); yy=3.52+row*.40
            sh=cube(name+"_shingle_%s_%02d"%("front" if side<0 else "back",row),(0,yy,z),(7.38,.07,.58),"roof",.01)
            sh.rotation_euler[0]=side*math.atan2(2.4,2.72)

def humanoid(name, skin="skin", cloth="cloth", hat=None, armor=False):
    sphere(name+"_head",(0,1.76,0),(.31,.34,.28),skin); cyl(name+"_torso",(0,1.12,0),.34,.9,"iron" if armor else cloth,8)
    sphere(name+"_eye_L",(-.11,1.72,-.255),(.045,.055,.025),"iron"); sphere(name+"_eye_R",(.11,1.72,-.255),(.045,.055,.025),"iron")
    if name == "woman":
        cone(name+"_dress",(0,.63,0),.50,.28,1.08,"red",8); sphere(name+"_hair",(0,1.88,.08),(.36,.42,.28),"bark")
        cube(name+"_apron",(0,.86,-.30),(.52,.72,.05),"white",.02)
    elif name == "wizard":
        sphere(name+"_beard",(0,1.52,-.25),(.16,.23,.12),"white"); cone(name+"_robe",(0,.62,0),.50,.3,1.25,"purple",8)
    elif name == "man":
        cube(name+"_tunic_belt",(0,1.0,-.28),(.68,.10,.08),"gold",.01)
    elif not armor: sphere(name+"_hair",(0,1.80,.08),(.33,.18,.28),"bark")
    for side in (-1,1):
        beam_between(name+"_arm_"+str(side),(side*.25,1.32,0),(side*.43,.83,-.04),.105,"iron" if armor else cloth)
        cyl(name+"_leg_"+str(side),(side*.15,.43,0),.12,.8,"iron" if armor else "wood",8)
    if hat: cone(name+"_hat",(0,2.04,0),.42,.06,.52,hat,8)

def simple_asset(asset):
    n=asset
    if asset=="oak_tree": foliage(n)
    elif asset=="pine_tree": foliage(n,pine=True)
    elif asset=="dead_tree": foliage(n,dead=True)
    elif asset=="bush":
        for i in range(6): sphere(n+"_leaf_%02d"%i,((i%3-.9)*.45,.55+(i%2)*.25,(i//3-.4)*.5),(.75,.65,.65),"leaf")
    elif asset=="rock": sphere(n,(0,.45,0),(1.1,.55,.9),"stone_light")
    elif asset=="cottage": cottage(n)
    elif asset=="inn": inn(n)
    elif asset in ("castle", "tower"):
        cube(n+"_keep",(0,2.5,0),(4,5,4),"stone",.1)
        for x in (-1.8,1.8):
            for z in (-1.8,1.8): cyl(n+"_turret",(x,3,z),.55,6,"stone_light",8)
        for x in (-1.2,0,1.2): cube(n+"_crenel",(x,5.5,-1.9),(.7,.7,.55),"stone_light")
        cube(n+"_gate",(0,1,-2.05),(1.2,2,.16),"wood")
    elif asset=="fence":
        for x in (-2,-1,0,1,2): cyl(n+"_post",(x,.8,0),.13,1.6,"wood",8)
        for y in (.55,1.15): cube(n+"_rail",(0,y,0),(4.5,.13,.13),"wood_light")
    elif asset == "barrel":
        cyl(n+"_body",(0,.65,0),.62,1.3,"wood",12); [torus(n+"_hoop",(0,y,0),.63,.055,"iron") for y in (.3,1.0)]
    elif asset == "well":
        # A masonry ring with visible water, timber posts, crank, roof and hanging bucket.
        for i in range(12):
            a=i*math.tau/12; r=1.02
            cube(n+"_stone_%02d"%i,(math.sin(a)*r,.175,math.cos(a)*r),(.62,.35,.42),"stone_light",.045).rotation_euler[1]=a
        for i in range(12):
            a=(i+.5)*math.tau/12; r=1.0
            cube(n+"_stone_upper_%02d"%i,(math.sin(a)*r,.52,math.cos(a)*r),(.59,.34,.4),"stone",.04).rotation_euler[1]=a
        cyl(n+"_water",(0,.53,0),.74,.05,"water",16)
        for x in (-1.15,1.15): cyl(n+"_post_"+str(x),(x,2.0,0),.13,2.8,"wood",8)
        beam_between(n+"_crossbeam",(-1.3,2.65,0),(1.3,2.65,0),.13,"wood")
        beam_between(n+"_crank",(-1.34,2.65,0),(-1.34,2.65,.52),.06,"iron")
        cyl(n+"_spool",(0,2.65,0),.13,2.0,"wood_light",10,rot=(0,math.pi/2,0))
        beam_between(n+"_rope",(0,2.58,0),(0,1.1,0),.022,"iron")
        cyl(n+"_bucket",(0,.93,0),.22,.34,"wood",10)
        # two pitched roof planes above the ring
        verts=[(-1.65,2.75,-1.05),(1.65,2.75,-1.05),(1.65,3.72,0),(-1.65,3.72,0),(-1.65,2.75,1.05),(1.65,2.75,1.05)]
        prism(n+"_roof",verts,[(0,1,2,3),(3,2,5,4)],"roof",.02)
    elif asset=="crate": cube(n,(0,.5,0),(1,1,1),"wood_light",.08); [cube(n+"_slat",(0,.5,z),(1.08,.12,.1),"wood") for z in (-.3,.3)]
    elif asset in ("table","bed"):
        cube(n+"_top",(0,1.0,0),(2.4,.18,1.25),"wood_light")
        for x in (-.95,.95):
            for z in (-.45,.45): cyl(n+"_leg",(x,.5,z),.1,1,"wood",8)
        if asset=="bed": cube(n+"_mattress",(0,1.18,0),(2.3,.25,1.15),"white"); cube(n+"_headboard",(0,1.65,.52),(2.4,1.0,.14),"wood")
    elif asset == "chair":
        cube(n+"_seat",(0,.82,0),(1.05,.16,1.0),"wood_light",.04)
        for x in (-.42,.42):
            for z in (-.38,.38): cyl(n+"_leg_%s_%s"%(x,z),(x,.4,z),.075,.8,"wood",8)
        # back at +Z so the front-facing -Z view reads as a seat and tall chair back.
        for x in (-.42,.42): cyl(n+"_back_post_"+str(x),(x,1.35,.42),.075,1.35,"wood",8)
        cube(n+"_backrest",(0,1.43,.42),(1.0,.48,.12),"wood_light",.04)
    elif asset == "chest":
        cube(n+"_box",(0,.52,0),(1.75,1.04,1.0),"wood_light",.06)
        # rounded half-cylinder lid, then broad iron straps and lock on the -Z face
        cyl(n+"_curved_lid",(0,1.04,0),.5,1.75,"wood",12,rot=(0,math.pi/2,0))
        cube(n+"_lid_cut",(0,.82,0),(1.9,.55,1.15),"wood_light",.01)
        for x in (-.55,.55):
            beam_between(n+"_strap_"+str(x),(x,.55,-.53),(x,1.48,-.08),.055,"iron")
            beam_between(n+"_strap_back_"+str(x),(x,.55,.53),(x,1.48,.08),.055,"iron")
        cube(n+"_lock",(0,.73,-.55),(.22,.25,.08),"gold",.02)
    elif asset=="sign": cube(n+"_post",(0,.8,0),(.15,1.6,.15),"wood"); cube(n+"_board",(0,1.55,0),(1.6,.65,.14),"wood_light")
    elif asset=="fountain": cyl(n+"_basin",(0,.25,0),1.3,.35,"stone_light",16); cyl(n+"_pedestal",(0,.8,0),.35,1.1,"stone",10); sphere(n+"_water",(0,1.45,0),(.5,.12,.5),"water")
    elif asset=="cave_entrance": sphere(n+"_mountain",(0,1.8,0),(2.5,2.0,1.2),"stone"); sphere(n+"_dark_opening",(0,1.0,-1.05),(1.1,1.2,.25),"iron")
    elif asset=="gravestone": cube(n+"_stone",(0,.65,0),(.8,1.3,.25),"stone_light",.15); sphere(n+"_roundtop",(0,1.3,0),(.4,.4,.13),"stone_light")
    elif asset=="mushroom": cyl(n+"_stem",(0,.3,0),.13,.6,"white",8); sphere(n+"_cap",(0,.65,0),(.5,.22,.5),"red")
    elif asset=="flowers":
        for i in range(5): cyl(n+"_stem"+str(i),((i-2)*.18,.3,0),.025,.6,"leaf",6); sphere(n+"_bloom"+str(i),((i-2)*.18,.65,0),(.13,.13,.13),"red" if i%2 else "gold")
    elif asset=="torch": cyl(n+"_handle",(0,.9,0),.09,1.8,"wood",8); cone(n+"_flame",(0,1.95,0),.2,.01,.55,"gold",8)
    elif asset == "slime":
        sphere(n+"_body",(0,.55,0),(.75,.55,.65),"slime"); sphere(n+"_eye_L",(-.2,.68,-.55),(.09,.1,.04),"white"); sphere(n+"_eye_R",(.2,.68,-.55),(.09,.1,.04),"white")
    elif asset == "pig":
        sphere(n+"_body",(0,.63,.12),(.83,.5,.66),"skin"); sphere(n+"_head",(0,.78,-.55),(.52,.42,.44),"skin")
        sphere(n+"_snout",(0,.72,-.96),(.28,.18,.10),"red")
        for x in (-.24,.24): sphere(n+"_nostril_"+str(x),(x,.74,-1.055),(.045,.045,.025),"iron")
        for x in (-.35,.35): cone(n+"_ear_"+str(x),(x,.98,-.56),.18,0,.34,"skin",6)
        for x in (-.55,.55):
            for z in (-.22,.47): cyl(n+"_leg_%s_%s"%(x,z),(x,.25,z),.12,.5,"skin",8)
        # curly tail at the rear (+Z)
        torus(n+"_curly_tail",(0,.83,.78),.18,.035,"skin",rot=(math.pi/2,0,0))
        sphere(n+"_eye_L",(-.18,.88,-.89),(.04,.05,.025),"iron"); sphere(n+"_eye_R",(.18,.88,-.89),(.04,.05,.025),"iron")
    elif asset == "duck":
        sphere(n+"_body",(0,.67,.12),(.68,.48,.98),"white"); sphere(n+"_neck",(0,1.0,-.48),(.32,.52,.32),"white"); sphere(n+"_head",(0,1.34,-.64),(.35,.32,.35),"white")
        cube(n+"_beak",(0,1.28,-1.00),(.42,.15,.42),"gold",.04)
        for x in (-.52,.52): sphere(n+"_wing_"+str(x),(x,.72,.18),(.24,.32,.66),"leaf_dark")
        for x in (-.22,.22):
            cyl(n+"_leg_"+str(x),(x,.26,-.03),.055,.42,"gold",6); cube(n+"_webbed_foot_"+str(x),(x,.06,-.24),(.28,.06,.38),"gold",.02)
        sphere(n+"_eye_L",(-.13,1.43,-.91),(.04,.045,.02),"iron"); sphere(n+"_eye_R",(.13,1.43,-.91),(.04,.045,.02),"iron")
    elif asset == "pillbug":
        # Segmenting along Z gives the familiar pillbug shell profile from above.
        for i in range(7):
            z=.48-i*.17; r=.48*(1-abs(i-3)*.075)
            sphere(n+"_shell_segment_%02d"%i,(0,.52,z),(r,.34,.20),"red")
        sphere(n+"_head",(0,.45,-.70),(.35,.27,.25),"red")
        for i,z in enumerate((.34,.04,-.27)):
            for side in (-1,1):
                beam_between(n+"_leg_%d_%d"%(i,side),(side*.27,.42,z),(side*.68,.13,z-.12),.045,"iron")
                beam_between(n+"_foot_%d_%d"%(i,side),(side*.68,.13,z-.12),(side*.78,.08,z-.30),.035,"iron")
        sphere(n+"_eye_L",(-.13,.56,-.89),(.055,.055,.03),"white"); sphere(n+"_eye_R",(.13,.56,-.89),(.055,.055,.03),"white")
    elif asset in ("bonca","dragon"):
        sphere(n+"_body",(0,1.0,.12),(1,.62,.82),"purple" if asset=="bonca" else "red")
        if asset=="bonca":
            # Bonca is a friendly long-necked purple beast, not a bipedal blob.
            beam_between(n+"_long_neck",(0,1.25,-.45),(0,2.25,-.88),.27,"purple")
            sphere(n+"_head",(0,2.38,-.95),(.45,.36,.48),"purple")
            for x in (-.62,.62):
                for z in (-.34,.48): cyl(n+"_leg_%s_%s"%(x,z),(x,.43,z),.16,.86,"purple",8)
            beam_between(n+"_tail_base",(0,.98,.72),(0,.82,1.75),.24,"purple"); beam_between(n+"_tail_tip",(0,.82,1.75),(0,1.15,2.25),.14,"purple")
            cube(n+"_mouth",(0,2.26,-1.39),(.34,.10,.08),"iron",.02); sphere(n+"_eye_L",(-.18,2.53,-1.31),(.05,.06,.025),"white"); sphere(n+"_eye_R",(.18,2.53,-1.31),(.05,.06,.025),"white")
        else:
            sphere(n+"_head",(0,1.45,-.7),(.58,.52,.55),"red")
            for x in (-.65,.65): cyl(n+"_leg",(x,.45,0),.18,.8,"red",8)
        if asset=="dragon":
            for x in (-1,1): cone(n+"_wing",(x*.75,1.45,.2),.65,0,1.1,"red",3)
    elif asset in ("knight","man","woman","wizard"): humanoid(n, armor=asset=="knight", hat="purple" if asset=="wizard" else None)
    elif asset in ("bow","sword","fist"):
        if asset=="sword": cube(n+"_blade",(0,1.0,0),(.12,1.8,.08),"stone_light"); cube(n+"_grip",(0,.05,0),(.18,.45,.18),"wood")
        elif asset=="bow":
            # open bent stave: a plane of segments, with a taut string on its chord.
            points=[(0,.22,0),(.20,.42,0),(.34,.70,0),(.39,1.0,0),(.34,1.30,0),(.20,1.58,0),(0,1.78,0)]
            for i in range(len(points)-1): beam_between(n+"_stave_%02d"%i,points[i],points[i+1],.048,"wood_light")
            beam_between(n+"_string",points[0],points[-1],.014,"iron")
        else:
            cube(n+"_palm",(0,.48,0),(.30,.32,.25),"skin",.06)
            for i in range(4):
                sphere(n+"_finger_"+str(i),(-.12+i*.08,.60,-.10),(.055,.09,.075),"skin")
            sphere(n+"_folded_thumb",(.18,.47,-.04),(.09,.16,.09),"skin")
            cyl(n+"_wrist",(0,.20,.04),.105,.40,"skin",10)
            cyl(n+"_sleeve",(0,.02,.07),.13,.18,"cloth",10)

ASSETS = ["oak_tree","pine_tree","dead_tree","bush","rock","cottage","inn","castle","tower","fence","barrel","crate","table","chair","bed","chest","sign","well","fountain","cave_entrance","gravestone","mushroom","flowers","torch","pig","duck","pillbug","bonca","slime","dragon","knight","man","woman","wizard","bow","sword","fist"]
CHARACTERS = {"pig", "duck", "pillbug", "bonca", "slime", "dragon", "knight", "man", "woman", "wizard"}
MANIFEST = []

def join_static(name):
    """Join static same-material parts for cheap instancing; keep character limbs separate."""
    if name in CHARACTERS: return
    apply_bevels()
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for material in sorted({o.data.materials[0].name if o.data.materials else '' for o in meshes}):
        # Re-query after every join: Blender removes the joined datablocks.
        group = [o for o in bpy.context.scene.objects if o.type == 'MESH' and (o.data.materials[0].name if o.data.materials else '') == material]
        if len(group) < 2: continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in group: o.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        bpy.ops.object.join(); group[0].name = name + "_" + (material.replace("Dink_", "").lower() or "mesh")

def place_on_ground(objs=None):
    meshes=[o for o in (objs or list(bpy.context.scene.objects)) if o.type == 'MESH']
    if not meshes: return
    lo=min((o.matrix_world @ Vector(c)).y for o in meshes for c in o.bound_box)
    for o in meshes: o.location.y -= lo
    bpy.context.view_layer.update()

def export_asset(name):
    reset(); root=bpy.data.objects.new(name, None); bpy.context.collection.objects.link(root)
    simple_asset(name)
    join_static(name)
    place_on_ground()
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if meshes:
        corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
        lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
        hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
        MANIFEST.append({"name": name, "path": "models/" + name + ".glb", "dimensions_m": [round(v, 3) for v in (hi-lo)], "base_y_m": round(lo.y, 3), "mesh_nodes": len(meshes), "front": "-Z", "up": "+Y"})
    for o in list(bpy.context.scene.objects):
        if o != root and o.parent is None: o.parent=root
    bpy.ops.object.select_all(action='DESELECT'); [o.select_set(True) for o in bpy.context.scene.objects if o.parent==root or o==root]; bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+".glb")), export_format='GLB', export_apply=True, use_selection=True, export_yup=False)

def move_to_collection(objs, collection):
    for o in objs:
        if o.name not in collection.objects: collection.objects.link(o)
        for old in list(o.users_collection):
            if old != collection: old.objects.unlink(o)

def add_source_asset(name, index):
    """Keep the editable library readable: one named collection per asset on a ground grid."""
    coll=bpy.data.collections.new("Asset_" + name); bpy.context.scene.collection.children.link(coll)
    before=set(bpy.context.scene.objects)
    simple_asset(name)
    made=[o for o in bpy.context.scene.objects if o not in before]
    place_on_ground(made)
    move_to_collection(made, coll)
    col=index % 7; row=index // 7; x=(col-3)*9.0; z=row*10.0
    root=bpy.data.objects.new("SOURCE_" + name, None); coll.objects.link(root); root.location=(x,0,z)
    for o in made:
        if o.parent is None: o.parent=root
    # Flat text faces upward in this Y-up authored scene and makes the library navigable.
    bpy.ops.object.text_add(location=(x,.02,z-3.2), rotation=(-math.pi/2,0,0))
    label=bpy.context.object; label.name="Label_"+name; label.data.body=name.replace('_',' '); label.data.align_x='CENTER'; label.data.size=.55; label.data.extrude=.01; label.hide_render=True
    move_to_collection([label], coll)
    return root

def make_contact_sheet():
    """Render the source library with an explicitly Y-up camera, never Blender's Z-up default view."""
    scene=bpy.context.scene
    scene.render.engine='BLENDER_EEVEE_NEXT'; scene.render.resolution_x=2048; scene.render.resolution_y=1536; scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'; scene.render.filepath=str(ART/'model_contact_sheet.png')
    scene.world.use_nodes=True
    bg=scene.world.node_tree.nodes.get('Background'); bg.inputs['Color'].default_value=(0.055,0.07,0.10,1); bg.inputs['Strength'].default_value=.45
    scene.view_settings.look='AgX - Medium High Contrast'; scene.view_settings.exposure=1.8
    # Soft large lights keep the contact sheet readable while retaining silhouette shading.
    for loc, energy, size in (((-22,30,-20),2600,12),((24,20,25),1800,10)):
        data=bpy.data.lights.new('Contact softbox','AREA'); data.energy=energy; data.shape='DISK'; data.size=size
        lamp=bpy.data.objects.new('Contact softbox',data); bpy.context.collection.objects.link(lamp); lamp.location=loc
        lamp.rotation_euler=(Vector((0,0,23))-Vector(loc)).to_track_quat('-Z','Y').to_euler()
    cam_data=bpy.data.cameras.new('Y-up contact camera'); cam_data.type='ORTHO'; cam_data.ortho_scale=64
    cam=bpy.data.objects.new('Y-up contact camera',cam_data); bpy.context.collection.objects.link(cam)
    cam.location=(0,52,-41); target=Vector((0,0,23)); cam.rotation_euler=(target-Vector(cam.location)).to_track_quat('-Z','Y').to_euler(); scene.camera=cam
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(ART/'dink_asset_library.blend'))
    bpy.ops.render.render(write_still=True)

def main():
    OUT.mkdir(parents=True, exist_ok=True); ART.mkdir(exist_ok=True); MANIFEST.clear(); reset(); make_materials()
    for name in ASSETS: export_asset(name)
    reset(); make_materials()
    for i, name in enumerate(ASSETS): add_source_asset(name, i)
    make_contact_sheet()
    (OUT / "manifest.json").write_text(json.dumps({"coordinate_system": "Godot Y-up, front -Z", "assets": MANIFEST}, indent=2) + "\n")
    print("Built", len(ASSETS), "Dink 3D assets in", OUT)

if __name__ == "__main__": main()
