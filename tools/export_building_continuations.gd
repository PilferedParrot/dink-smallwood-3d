extends SceneTree
# Export exact source/UV polygons before any donor table is generated.
const BUILDINGS := preload("res://scripts/sprite_buildings.gd")
var out := ""
var images := {}
var buildings
func _initialize() -> void:
	_run.call_deferred()
func _save(source: String, img: Image) -> void:
	if images.has(source): return
	var path := out.path_join(source.sha256_text()+".png")
	img.save_png(path)
	images[source] = path
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source-out="): out = arg.trim_prefix("--source-out=")
	if out.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(out)
	var seqs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sequences.json")).sequences
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var fits: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://prototype/facades.json"))
	buildings = BUILDINGS.new(seqs,world,fits,0.025)
	for path in fits:
		if not str(path).begins_with("assets/") or not fits[path].has("faces"): continue
		var raw: Image = buildings.image(path)
		var fit: Dictionary = fits[path]
		if fit.has("polys"):
			var occluders: Array = []
			for poly in fit.get("occluders",[]):
				var p := PackedVector2Array()
				for q in poly: p.append(Vector2(float(q[0]),float(q[1])))
				occluders.append(p)
			var body: Image = buildings._without(raw,occluders)
			_save(path+"#0",body); _save(path+"#1",body); _save(path+"#2",raw)
		else: _save(path+"#0",raw); _save(path+"#1",raw)
		var made: Dictionary = buildings.house(path,Rect2(Vector2.ZERO,Vector2(raw.get_size())),{"details":[],"roof":[],"ground":[]},"","",false)
		made.node.free()
	for kit in fits.get("_kit_buildings",[]):
		var k: Array = buildings.kit_prepare(kit)
		_save("kit:"+str(kit.name)+"#0",k[0]); _save("kit:"+str(kit.name)+"#1",k[1])
		for dm in kit.get("dormers",[]): _save("dormer:"+str(dm.path)+"#0",buildings.image(str(dm.path)))
		var node: Node3D = buildings.kit(kit); node.free()
	for path in fits.get("_huts",{}):
		_save(path+"#0",buildings.image(path))
		buildings.hut_surfaces(path)
	# Use actual placed roof heights/footprints, including cross-screen pieces.
	var pieces: Array = []
	var houses: Array = []
	for sn in world.screens:
		var n := int(sn)
		for sprite in world.screens[sn].sprites:
			if int(sprite.get("type",1)) == 2: continue
			var frame: Dictionary = buildings.sprite_frame(sprite)
			if frame.is_empty(): continue
			if fits.get("_roof_pieces",{}).has(str(frame.path)): pieces.append([sprite,n])
			if buildings.is_fitted(sprite): houses.append([sprite,n])
	for house in houses:
		var rect: Rect2 = buildings.world_rect(house[0],house[1])
		var fit: Dictionary = fits[str(buildings.sprite_frame(house[0]).path)]
		for piece in pieces:
			var got: Array = buildings.claim(fit,rect,piece[0],piece[1])
			if got.is_empty(): continue
			var path: String = str(buildings.sprite_frame(piece[0]).path)
			var surfaces: Array = []
			if got[0] == "ground":
				_save(path+"#0",buildings.image(path))
				buildings._ground_piece(surfaces,[piece[0],got[2],got[1].position],rect.position,buildings._texture(buildings.filled(buildings.image(path))))
			elif got[0] == "roof":
				var r := [piece[0],got[2],got[1].position-rect.position,got[3]]
				var raw: Image = buildings._roof_piece_image(r)
				_save(path+"#0",raw)
				buildings._roof_piece(surfaces,r,fit,buildings._texture(buildings.filled(raw)))
	buildings.continuation.flush_audit()
	var f := FileAccess.open(out.path_join("images.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(images))
	print("CONTINUATION EXPORT images=",images.size()," polygons=",buildings.continuation.audit.size())
	quit()
