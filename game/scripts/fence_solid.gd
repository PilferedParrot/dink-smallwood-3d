extends RefCounted
# Rail fences stand as solid posts and rails (docs/DIRECTION.md, "Solid fences", October 7, M3 solid unit).
#
# A fence's art (lands/Fence fence-01..06, the island's isle-07 and isle-08) is a picture of a 3D fence taken by the original
# camera, screen = (X, Z - Y). tools/fence_fit.py reads its posts (where they stand: foot row, centre, the module's width and
# height) and its rails (the bar from one post to the next: its bottom's height over each) from the pixels, and writes
# game/prototype/fences.json. This builds them: each post a square prism, each rail a square bar between two posts, all
# textured by the projection through the original camera (a vertex's uv is where the original camera draws it in the art),
# so from the original camera the fence is the art's own pixels, and from anywhere else it is a fence with a top, a back and
# two ends, whose faces show the art's pixels where the camera sees them and the nearest ones where it does not (a post's
# side shows its edge column, a bar's top the lit rows).
# A post the map shares between two segments (the next segment starts where this one ends: the original's chains put the
# last post of one within 3 px of the first of the next; the same segment placed on two screens at a seam) is one post, and the
# rails that meet it end on it: the registry below holds the posts of the scene, by where they stand in the world. Where two
# bars lie along one line at one height (one segment on two screens, two column pieces the map overlaps) the part already
# standing is not built again. The rope ties at the joints are boxes a little wider than the post (the "Ties" mesh). The
# collision is the source's (game.gd): the body on the hardbox this keeps is only for rays, as the card it replaces had.
const SCALE := 0.025
const MERGE := 6.0 # px: posts this close in the world are one post (a chain's segments stand 1-5 px apart; posts of one fence stand 35 or more apart)

var world # fp_world.gd
var data: Dictionary = {}
var posts: Array = [] # [{p: Vector2 (world px), owner: Node3D}]: the posts standing in this scene
var rails: Array = [] # [{a: Vector2, b: Vector2, ha, hb, t0, t1, owner}]: the bars standing in this scene
var materials: Dictionary = {} # path -> StandardMaterial3D

func setup(fp_world) -> void:
	world = fp_world
	var path := "res://prototype/fences.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	data = parsed if parsed is Dictionary else {}

# A scene is built anew: nothing stands yet.
func reset() -> void:
	posts.clear()
	rails.clear()

func has(path: String) -> bool:
	return data.has("arts") and (data.arts as Dictionary).has(path)

func _material(path: String) -> StandardMaterial3D:
	if materials.has(path): return materials[path]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.texture_repeat = false
	material.albedo_texture = world.clean_texture(path)
	materials[path] = material
	return material

# The fence's unit directions along a line and across it (across: toward the original viewer, +Z), as fence_fit.py unit_n.
func _un(u: Vector2) -> Array:
	var v := Vector2(1,0) if u.length() < 1e-9 else u.normalized()
	var n := Vector2(-v.y,v.x)
	if n.y < 0.0 or (n.y == 0.0 and n.x > 0.0): n = -n
	return [v,n]

# The eight corners (x, z, height) of a bar: index = along*4 + across*2 + up. A post: along its line u (w), across it (d), H high.
func _corners_post(c: Vector2, u: Vector2, w: float, d: float, h: float) -> Array:
	var un := _un(u)
	var out: Array = []
	for su in [-0.5,0.5]:
		for sn in [-0.5,0.5]:
			for y in [0.0,h]:
				var q: Vector2 = c+(un[0] as Vector2)*(w*su)+(un[1] as Vector2)*(d*sn)
				out.append(Vector3(q.x,y,q.y))
	return out

# A bar from plan point pa (bottom at height ha) to pb (hb): d across the line, th high.
func _corners_rail(pa: Vector2, pb: Vector2, ha: float, hb: float, d: float, th: float) -> Array:
	var un := _un(pb-pa)
	var out: Array = []
	for hp in [[pa,ha],[pb,hb]]:
		for sn in [-0.5,0.5]:
			for y in [0.0,th]:
				var q: Vector2 = (hp[0] as Vector2)+(un[1] as Vector2)*(d*sn)
				out.append(Vector3(q.x,float(hp[1])+y,q.y))
	return out

# The six faces of a box, by [along, across, up] of their corners (index = along*4 + across*2 + up).
const QUADS := [
	[[0,1,0],[1,1,0],[1,1,1],[0,1,1]], # front (across +)
	[[1,0,0],[0,0,0],[0,0,1],[1,0,1]], # back
	[[0,0,1],[1,0,1],[1,1,1],[0,1,1]], # top
	[[0,1,0],[1,1,0],[1,0,0],[0,0,0]], # bottom
	[[0,0,0],[0,1,0],[0,1,1],[0,0,1]], # end 0
	[[1,1,0],[1,0,0],[1,0,1],[1,1,1]], # end 1
]

# A bar's mesh faces added to `tool`: geometry from `geo` (node-local metres), texture coordinates from `art` (the same bar
# in the art's own pixels: where the original camera draws each corner). Each is 8 corners as _corners_*. A face the original
# camera sees (its normal has a +Z part, or it is the top) takes the art's pixels where the camera draws it. A face it does not
# see is not in the art: it takes the face opposite, the front's (the back, the bottom, the ends: the same pixels, so a post
# seen from behind is the post seen from the front), or, where even the front is edge-on (a rail along the depth axis), the
# top's. Without this, a back face reads the art's pixels just behind the front's and a bottom the rail's staircase edge.
func _box(tool: SurfaceTool, geo: Array, art: Array) -> void:
	var size: Vector2 = _size
	var along := Vector2((art[4] as Vector3).x-(art[0] as Vector3).x,(art[4] as Vector3).z-(art[0] as Vector3).z)
	var across := Vector2((art[2] as Vector3).x-(art[0] as Vector3).x,(art[2] as Vector3).z-(art[0] as Vector3).z)
	# The faces by QUADS' order: front (across 1), back (across 0), top, bottom, end 0 (along 0), end 1 (along 1).
	var nrm := across.normalized() if across.length() > 0.0 else Vector2.ZERO
	var alg := along.normalized() if along.length() > 0.0 else Vector2.ZERO
	var seen := [nrm.y > 0.01,-nrm.y > 0.01,true,false,-alg.y > 0.01,alg.y > 0.01]
	# The plane a face the camera does not see takes its pixels from: the first vertical face it does see, as [axis, value].
	var plane := []
	for pick in [[0,[1,1]],[5,[0,1]],[4,[0,0]],[1,[1,0]]]:
		if bool(seen[int(pick[0])]):
			plane = pick[1]
			break
	# The projected centre, to pull a face seen edge-on into the box rather than onto its silhouette's pixel boundary.
	var centre := Vector2.ZERO
	for q in art: centre += Vector2((q as Vector3).x,(q as Vector3).z-(q as Vector3).y)
	centre /= float(art.size())
	for qi in QUADS.size():
		var quad: Array = QUADS[qi]
		var uv: Array = []
		var lo := Vector2(INF,INF)
		var hi := Vector2(-INF,-INF)
		var idx: Array = []
		for c in quad:
			var i := int(c[0])*4+int(c[1])*2+int(c[2])
			idx.append(i)
			var src := i
			if not bool(seen[qi]):
				if plane.is_empty():
					src = int(c[0])*4+int(c[1])*2+1 # nothing vertical is seen: the top's pixels
				else:
					var cc := [int(c[0]),int(c[1]),int(c[2])]
					cc[int(plane[0])] = int(plane[1])
					src = cc[0]*4+cc[1]*2+cc[2]
			var a: Vector3 = art[src]
			var p := Vector2(a.x,a.z-a.y)
			uv.append(p)
			lo = lo.min(p)
			hi = hi.max(p)
		for k in uv.size():
			var p: Vector2 = uv[k]
			if hi.x-lo.x < 0.01: p.x += clampf(centre.x-p.x,-0.5,0.5)
			if hi.y-lo.y < 0.01: p.y += clampf(centre.y-p.y,-0.5,0.5)
			uv[k] = Vector2(p.x/size.x,p.y/size.y)
		for t in [0,1,2,0,2,3]:
			tool.set_uv(uv[t])
			tool.add_vertex(geo[idx[t]])

var _size := Vector2.ONE # the art being built (px): uv = px / size

# Where world pixel w is: the post already standing within MERGE of it (its place), else this one's own (and it is built).
func _resolve(w: Vector2, owner: Node3D) -> Array:
	var best := -1
	var best_d := INF
	for i in posts.size():
		if not is_instance_valid(posts[i].owner): continue
		var q: Vector2 = posts[i].p
		if absf(q.x-w.x) > MERGE or absf(q.y-w.y) > MERGE: continue
		var d := q.distance_to(w)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0: return [posts[best].p,false]
	posts.append({"p": w,"owner": owner})
	return [w,true]

# The parts of a bar (world px: from a to b, bottom heights ha, hb; its span u0..u1 as fractions of a to b) that no bar already
# standing covers: [[s0, s1], ...]. A bar covers where the other lies along the same line (within 3 px across, 2.5 px in height,
# 6 px of overlap at least). The same segment placed on two screens (409's and 408's), a segment standing on a post the
# previous one ends on, two column pieces the map places a few rows apart: the bars in common are built once.
func _uncovered(a: Vector2, b: Vector2, ha: float, hb: float, u0: float, u1: float) -> Array:
	var length := a.distance_to(b)
	if length < 0.01: return []
	var dir := (b-a)/length
	var cover: Array = [] # [s0, s1] covered intervals
	for r in rails:
		if not is_instance_valid(r.owner): continue
		var ra: Vector2 = r.a
		var rb: Vector2 = r.b
		var rl := ra.distance_to(rb)
		if rl < 0.01: continue
		var rdir := (rb-ra)/rl
		if absf(dir.cross(rdir)) > 0.06: continue # not along the same line
		# Both ends of the other's standing part, in this bar's terms.
		var p0 := ra.lerp(rb,float(r.t0))
		var p1 := ra.lerp(rb,float(r.t1))
		var h0 := lerpf(float(r.ha),float(r.hb),float(r.t0))
		var h1 := lerpf(float(r.ha),float(r.hb),float(r.t1))
		# Along this bar, the other's standing part runs from q0 to q1 (px from a); across: its distance from the line.
		var q0 := (p0-a).dot(dir)
		var q1 := (p1-a).dot(dir)
		var c0 := absf((p0-a).cross(dir))
		var c1 := absf((p1-a).cross(dir))
		if c0 > 3.0 or c1 > 3.0: continue
		var lo := minf(q0,q1)
		var hi := maxf(q0,q1)
		# Heights: the other's at its ends against this bar's at the same places.
		var ok := true
		for pair in [[q0,h0],[q1,h1]]:
			var t := float(pair[0])/length
			if absf(lerpf(ha,hb,t)-float(pair[1])) > 2.5: ok = false
		if not ok: continue
		lo = maxf(lo,u0*length)
		hi = minf(hi,u1*length)
		if hi-lo > 0.0: cover.append([lo,hi])
	cover.sort_custom(func(x, y): return x[0] < y[0])
	var out: Array = []
	var at := u0*length
	for c in cover:
		if float(c[0]) > at+4.0: out.append([at/length,float(c[0])/length])
		at = maxf(at,float(c[1]))
	if u1*length > at+4.0: out.append([at/length,u1])
	return out

# Stand the fence of entity e (screen `screen`) in `node`: its posts and bars, and the body for rays on its hardbox. Returns
# false when there is nothing to stand (the caller keeps its card).
func add(node: Node3D, e: Dictionary, id: int, key: String, collision: bool, screen: int) -> bool:
	var path: String = world.frame_path(e)
	if not has(path): return false
	var texture: Texture2D = world.clean_texture(path)
	if texture == null: return false
	var art: Dictionary = data.arts[path]
	var module: Dictionary = data.modules[str(art.module)]
	var d: Dictionary = world.host._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
	var f := maxf(0.01,float(e.get("size",100))/100.0)
	var hot := Vector2(float(d.get("dx",0)),float(d.get("dy",0)))
	var here := Vector2(float(e.get("x",0)),float(e.get("y",0)))
	var origin: Vector2 = world.screen_origin(screen)
	_size = Vector2(float(art.size[0]),float(art.size[1]))
	var clip := Rect2(-1e9,-1e9,2e9,2e9)
	var cr: Array = e.get("clip_rect",[0,0,0,0])
	if cr.size() == 4 and (int(cr[2]) > 0 or int(cr[3]) > 0): clip = Rect2(float(cr[0]),float(cr[1]),float(cr[2])-float(cr[0]),float(cr[3])-float(cr[1]))
	var w := float(module.w)
	var dd := float(module.d)
	var hh := float(module.H)
	var th := float(module.th)
	var td := float(art.td)
	# An entity the original does not draw (type 2, hidden) stands nothing, and takes no post from one that does.
	var drawn := int(e.get("type",1)) != 2 and int(e.get("active",1)) != 0 and int(e.get("nodraw",0)) == 0 and int(e.get("disabled",0)) == 0
	var tool_posts := SurfaceTool.new()
	tool_posts.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tool_rails := SurfaceTool.new()
	tool_rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tool_ties := SurfaceTool.new()
	tool_ties.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ties := 0
	var tie := float(module.get("e",0.0))
	var holder := Node3D.new()
	holder.name = "Fence"
	node.add_child(holder)
	# The posts: each at its world place, merged with a neighbour's within MERGE.
	var spec: Array = art.posts
	var pi := -1
	var canon: Array = [] # per post: its place in world px (after merging), or null when clipped away
	var fresh: Array = [] # per post: true if this entity stands it (no other post was there)
	var built := 0
	for p in spec:
		pi += 1
		var ax := float(p.x)
		var az := float(p.z)
		if not drawn or ax < clip.position.x or ax > clip.end.x:
			canon.append(null)
			fresh.append(false)
			continue
		var wpos := origin+here+(Vector2(ax,az)-hot)*f
		var r := _resolve(wpos,holder)
		canon.append(r[0])
		fresh.append(bool(r[1]))
		if not bool(r[1]): continue
		var u := Vector2(float(p.u[0]),float(p.u[1]))
		# Geometry in this node's local metres: its place (the canonical one), the art's directions; uv from the art's own.
		var local := ((r[0] as Vector2)-origin-here)/f+hot # art px of the canonical place
		var geo := _scaled(_corners_post(local,u,w,dd,hh),hot,f)
		var uvc := _corners_post(Vector2(ax,az),u,w,dd,hh)
		_box(tool_posts,geo,uvc)
		built += 1
		# The rope ties at the rails' joints on this post: a box a little wider and deeper than the post, as high as a rail.
		if tie > 0.0:
			for hgt in _joints(art,pi):
				var tg := _scaled(_lift(_corners_post(local,u,w+2.0*tie,dd+2.0*tie,th),hgt),hot,f)
				var tu := _lift(_corners_post(Vector2(ax,az),u,w+2.0*tie,dd+2.0*tie,th),hgt)
				_box(tool_ties,tg,tu)
				ties += 1
	# The bars: between the canonical posts; the clip rect cuts them where it cuts the art.
	var spans := 0
	var last := (art.bays as Array).size()-1
	for bay in art.bays:
		var ia := int(bay.a)
		var ib := int(bay.b)
		var pa: Variant = canon[ia]
		var pb: Variant = canon[ib]
		var sa: Dictionary = spec[ia]
		var sb: Dictionary = spec[ib]
		var t0 := 0.0
		var t1 := 1.0
		var xa := float(sa.x)
		var xb := float(sb.x)
		if absf(xb-xa) > 0.01:
			var ta := (clip.position.x-xa)/(xb-xa)
			var tb := (clip.end.x-xa)/(xb-xa)
			t0 = maxf(t0,minf(ta,tb))
			t1 = minf(t1,maxf(ta,tb))
		elif xa < clip.position.x or xa > clip.end.x:
			continue
		if not drawn or t1-t0 < 0.03: continue
		# A post that is not here (clipped) leaves its end where the clip cut the bar; the canonical places otherwise.
		var wa := origin+here+(Vector2(xa,float(sa.z))-hot)*f
		var wb := origin+here+(Vector2(xb,float(sb.z))-hot)*f
		if pa != null: wa = pa
		if pb != null: wb = pb
		var length := (Vector2(xb,float(sb.z))-Vector2(xa,float(sa.z))).length()
		for r in bay.rails:
			var ha := float(r.a)
			var hb := float(r.b)
			# The rail runs past a free end post (one no other segment's post stood on), as the art draws it.
			var u0 := t0
			var u1 := t1
			if int(bay.a) == 0 and bool(fresh[0]) and t0 <= 0.0: u0 = -float(r.get("ea",0))/length
			if int(bay.b) == last+1 and bool(fresh[last+1]) and t1 >= 1.0: u1 = 1.0+float(r.get("eb",0))/length
			for piece in _uncovered(wa,wb,ha,hb,u0,u1):
				var s0 := float(piece[0])
				var s1 := float(piece[1])
				rails.append({"a": wa,"b": wb,"ha": ha,"hb": hb,"t0": s0,"t1": s1,"owner": holder})
				var la := (wa-origin-here)/f+hot
				var lb := (wb-origin-here)/f+hot
				var geo := _scaled(_corners_rail_span(la,lb,ha,hb,td,th,s0,s1),hot,f)
				var aa := Vector2(xa,float(sa.z))
				var ab := Vector2(xb,float(sb.z))
				var uvc := _corners_rail_span(aa,ab,ha,hb,td,th,s0,s1)
				_box(tool_rails,geo,uvc)
				spans += 1
	for pair in [[tool_posts,"Posts",built],[tool_rails,"Rails",spans],[tool_ties,"Ties",ties]]:
		if int(pair[2]) == 0: continue
		var tool: SurfaceTool = pair[0]
		var mesh := tool.commit()
		var instance := MeshInstance3D.new()
		instance.name = str(pair[1])
		instance.mesh = mesh
		instance.material_override = _material(path)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		holder.add_child(instance)
	var height := maxf(0.2,world.sprite_height(e)*SCALE*f)
	node.set_meta("height",height)
	node.set_meta("actor",false)
	node.set_meta("solid_fence",true)
	holder.set_meta("posts_built",built)
	holder.set_meta("bars_built",spans)
	_hit_body(node,e,id,key,collision,height)
	return true

# The heights of the joints on post i: the bottoms of the rails that end on it, rails within 4.5 px of height one joint
# (the two bays' rails meet a middle post at one tie), at the cluster's mean (fence_fit.py lashings).
func _joints(art: Dictionary, i: int) -> Array:
	var hs: Array = []
	for bay in art.bays:
		for r in bay.rails:
			if int(bay.a) == i: hs.append(float(r.a))
			if int(bay.b) == i: hs.append(float(r.b))
	hs.sort()
	var out: Array = []
	var cluster: Array = []
	for k in hs.size()+1:
		var hgt: Variant = hs[k] if k < hs.size() else null
		if not cluster.is_empty() and (hgt == null or float(hgt)-float(cluster[-1]) > 4.5):
			var sum := 0.0
			for c in cluster: sum += float(c)
			out.append(sum/cluster.size())
			cluster = []
		if hgt != null: cluster.append(hgt)
	return out

func _lift(corners: Array, h: float) -> Array:
	var out: Array = []
	for c in corners: out.append(Vector3((c as Vector3).x,(c as Vector3).y+h,(c as Vector3).z))
	return out

# The bar from a to b, cut to [t0, t1] of its length (corners as _corners_rail).
func _corners_rail_span(a: Vector2, b: Vector2, ha: float, hb: float, d: float, th: float, t0: float, t1: float) -> Array:
	var pa := a.lerp(b,t0)
	var pb := a.lerp(b,t1)
	var un := _un(b-a)
	var res: Array = []
	var ya := lerpf(ha,hb,t0)
	var yb := lerpf(ha,hb,t1)
	for hp in [[pa,ya],[pb,yb]]:
		for sn in [-0.5,0.5]:
			for y in [0.0,th]:
				var q: Vector2 = (hp[0] as Vector2)+(un[1] as Vector2)*(d*sn)
				res.append(Vector3(q.x,float(hp[1])+y,q.y))
	return res

# Corners in art px (x, height, z) to node-local metres: px from the hotspot, scaled.
func _scaled(corners: Array, hot: Vector2, f: float) -> Array:
	var out: Array = []
	for c in corners:
		var q: Vector3 = c
		out.append(Vector3((q.x-hot.x)*SCALE*f,q.y*SCALE*f,(q.z-hot.y)*SCALE*f))
	return out

# The body rays hit (aim, projectiles): on the source's hardbox, as the card's was (fp_world add_billboard).
func _hit_body(node: Node3D, e: Dictionary, id: int, key: String, collision: bool, height: float) -> void:
	var passable := key == "fence" and int(e.get("hard",0)) != 0
	if not collision or passable or e.get("warp") != null: return
	var body := StaticBody3D.new()
	body.name = "HitBody"
	body.set_meta("entity_id",id)
	body.collision_layer = 2 if not str(e.get("script","")).is_empty() else 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var rect: Rect2 = world.hard_rect(e)
	box.size = Vector3(maxf(0.2,rect.size.x*SCALE),height,maxf(0.2,rect.size.y*SCALE))
	shape.position = world.point(rect.get_center().x,rect.get_center().y)-node.position
	shape.position.y = height*0.5
	shape.shape = box
	body.add_child(shape)
	node.add_child(body)
