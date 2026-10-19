# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Inferred native-pixel continuation, never new painting. The immutable donor
# table is built from actual emitted polygons by tools/building_continuations.py.
extends RefCounted

const TABLE := "res://data/building_continuations.json"
const FACADES := "res://prototype/facades.json"
var scale: float
var faces: Dictionary = {}
var atlases: Dictionary = {}
var audit: Dictionary = {}
var audit_path := ""
var mask_mode := false
var textures: Dictionary = {}
var owners: Dictionary = {}
var supports: Dictionary = {}
var donors: Dictionary = {}
var source_owners: Dictionary = {}

func _init(s: float) -> void:
	scale = s
	var table := TABLE
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--building-continuation-audit="):
			audit_path = arg.trim_prefix("--building-continuation-audit=")
		if arg == "--building-source-mask": mask_mode = true
		if arg.begins_with("--building-continuation-table="): table = arg.trim_prefix("--building-continuation-table=")
	if FileAccess.file_exists(table):
		var data = JSON.parse_string(FileAccess.get_file_as_string(table))
		if data is Dictionary and int(data.get("format",0)) == 1 and str(data.get("facades_sha256","")) == FileAccess.get_sha256(FACADES):
			faces = data.get("faces",{})
			atlases = data.get("atlases",{})
			for alias in data.get("aliases",{}): faces[alias] = faces[data.aliases[alias]]
			for alias in data.get("atlas_aliases",{}): faces[alias] = {"atlas_id":data.atlas_aliases[alias]}
			if "--building-no-continuation" in OS.get_cmdline_user_args(): faces.clear()
		else: push_warning("Stale building continuation table; regenerate it from the fitted source")

# Composed doors/signs stay authored; continuation takes base material pixels,
# so a nearby door can neither be overwritten nor copied into a missing strip.
func register_source(texture: Texture2D, source: Image, dither: PackedByteArray, donor: Image = null) -> void:
	var bytes := source.get_data()
	var mask := PackedByteArray()
	mask.resize(source.get_width()*source.get_height())
	for i in mask.size(): mask[i] = 1 if bytes[i*4+3] >= 128 and not dither[i] else 0
	supports[texture.get_instance_id()] = mask
	source_owners[texture.get_instance_id()] = weakref(texture)
	if donor != null: donors[texture.get_instance_id()] = donor.get_data()

func register_donor(texture: Texture2D, donor: Image) -> void:
	var img: Image = donor.duplicate()
	if img.is_compressed(): img.decompress()
	img.convert(Image.FORMAT_RGBA8); img.clear_mipmaps()
	donors[texture.get_instance_id()] = img.get_data()
	source_owners[texture.get_instance_id()] = weakref(texture)

func key_of(source: String, uv: Array[Vector2]) -> String:
	var sorted := uv.duplicate()
	sorted.sort_custom(func(a: Vector2,b: Vector2): return a.x < b.x if a.x != b.x else a.y < b.y)
	var words := PackedStringArray()
	for p in sorted: words.append("%.2f,%.2f" % [p.x,p.y])
	return source + "|" + ";".join(words)

func flush_audit() -> void:
	if audit_path.is_empty(): return
	var file := FileAccess.open(audit_path,FileAccess.WRITE)
	if file == null: push_error("Cannot write building continuation audit"); return
	file.store_string(JSON.stringify({"polygons":audit.values()}))

# Returns [] for an unchanged polygon; otherwise its same geometry/UV lattice
# with a private per-face atlas. Keeping per-face atlases prevents stone donors
# from leaking onto thatch which happens to sample the same missing atlas pixel.
func face(pts: Array[Vector3], uv: Array[Vector2], texture: Texture2D, source: String, group: String = "", point_scale: float = 0.0) -> Array:
	if source.is_empty(): return []
	var vertex_scale := point_scale if point_scale > 0.0 else scale
	var key := key_of(source,uv)
	if not audit_path.is_empty() and not audit.has(key):
		var p := []; var u := []
		for q in pts: p.append([q.x,q.y,q.z])
		for q in uv: u.append([q.x,q.y])
		audit[key] = {"key":key,"source":source,"group":source+"|"+group,"pts":p,"uv":u,"point_scale":vertex_scale}
	if not faces.has(key): return []
	var entry: Dictionary = faces[key]
	var paint: Dictionary = atlases.get(entry.get("atlas_id",""),entry)
	var atlas := _atlas(texture,key,paint)
	var rect: Array = paint.rect
	var offset := Vector2(float(rect[0]),float(rect[1]))
	var size := Vector2(float(rect[2]),float(rect[3]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1,pts.size()-1):
		for j in [0,i,i+1]:
			st.set_uv((uv[j]-offset)/size)
			st.add_vertex(pts[j]*vertex_scale)
	return [st.commit(),atlas]

# The hut's reflected source bands repeat around its ring. Reuse one atlas
# and one deterministic surface for identical donor maps instead of exhausting
# render-priority slots with repeated instances of the same source quad.
func append_merged(out: Array, additions: Array) -> void:
	var tools := {}
	var order: Array = []
	for sf in additions:
		var id: int = sf[1].get_instance_id()
		if not tools.has(id):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[id] = st; order.append(sf[1])
		var arrays: Array = sf[0].surface_get_arrays(0)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i in positions.size():
			tools[id].set_uv(uv[i]); tools[id].add_vertex(positions[i])
	order.sort_custom(func(a,b): return int(a.get_meta("continuation_source_order",0)) < int(b.get_meta("continuation_source_order",0)))
	for texture in order: out.append([tools[texture.get_instance_id()].commit(),texture])

func _atlas(texture: Texture2D, key: String, entry: Dictionary) -> Texture2D:
	if entry.copies.is_empty() and not mask_mode:
		texture.set_meta("continuation_source_order",entry.get("source_order",0))
		return texture
	var cache_key := "%d:%s" % [texture.get_instance_id(),entry.get("atlas_key",key)]
	if textures.has(cache_key): return textures[cache_key]
	for old in owners.keys():
		if owners[old].get_ref() == null:
			owners.erase(old); textures.erase(old)
	for old in source_owners.keys():
		if source_owners[old].get_ref() == null:
			source_owners.erase(old); supports.erase(old); donors.erase(old)
	var original: Image = texture.get_image().duplicate()
	if original.is_compressed(): original.decompress()
	original.convert(Image.FORMAT_RGBA8)
	original.clear_mipmaps()
	var source_data: PackedByteArray = donors.get(texture.get_instance_id(),original.get_data())
	var authored: PackedByteArray = supports.get(texture.get_instance_id(),PackedByteArray())
	var rect: Array = entry.rect
	var x0 := int(rect[0]); var y0 := int(rect[1])
	var width := int(rect[2]); var height := int(rect[3])
	var img := Image.create(width,height,false,Image.FORMAT_RGBA8)
	if mask_mode: img.fill(Color.BLACK)
	else:
		# Source materials repeat. Continue that same baseline into crop gutters;
		# transparent black padding would alter otherwise untouched mip samples.
		var y := 0
		while y < height:
			var sy := posmod(y+y0,original.get_height())
			var rows := mini(height-y,original.get_height()-sy)
			var x := 0
			while x < width:
				var sx := posmod(x+x0,original.get_width())
				var cols := mini(width-x,original.get_width()-sx)
				img.blit_rect(original,Rect2i(sx,sy,cols,rows),Vector2i(x,y))
				x += cols
			y += rows
	var data := img.get_data()
	for pair in entry.copies:
		var pixel := int(pair[0])
		var tx := pixel % width + x0
		var ty := int(pixel / width) + y0
		if not authored.is_empty() and tx >= 0 and ty >= 0 and tx < original.get_width() and ty < original.get_height() and authored[ty*original.get_width()+tx]: continue
		var target := pixel*4
		var donor := int(pair[1])*4
		if mask_mode:
			for c in 4: data[target+c] = 255
		else:
			for c in 4: data[target+c] = source_data[donor+c]
	img.set_data(width,height,false,Image.FORMAT_RGBA8,data)
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	out.resource_name = "inferred_continuation_mask" if mask_mode else "inferred_continuation"
	out.set_meta("continuation_key",key)
	out.set_meta("continuation_atlas",entry.get("atlas_key",""))
	out.set_meta("continuation_source_order",entry.get("source_order",0))
	textures[cache_key] = out; owners[cache_key] = weakref(texture)
	return out
