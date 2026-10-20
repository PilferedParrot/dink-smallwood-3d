# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Inferred overhead materials: source rectangles and room census are derived by
# tools/ceiling_donors.py. No authored ceiling is claimed. Geometry stays in fp_world.
extends RefCounted
const S := 0.025
var world
var data: Dictionary
var materials: Dictionary = {}
var shaders: Dictionary = {}

func _init(fp) -> void:
 world = fp
 data = JSON.parse_string(FileAccess.get_file_as_string("res://data/ceilings.json"))

func room(number: int) -> Dictionary:
 return data.rooms.get(str(number), {})

func material(number: int, role: String) -> Material:
 var info := room(number)
 if not info.get("room", false) or info.get(role) == null: return null
 var donor: Dictionary = info[role]
 var key := JSON.stringify(donor)+":"+role
 if materials.has(key): return materials[key]
 var tiled := str(donor.get("mode","")) == "authored-tiles"
 var path := str(donor.get("path",""))
 var filtered := str(donor.filter) == "wall-plaster"
 # Identical filtering to the fitted wall, including the row trend. Crop only
 # AFTER this operation so the ceiling never invents a sharper plaster path.
 var source: Image = tile_arrangement(donor.tiles) if tiled else (world.solids.plaster_texture(path).get_image() if filtered else world.sprite_image(path))
 var r: Array = donor.rect
 var crop := source.get_region(Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3])))
 var tile := crop if tiled else reflected(crop)
 tile.generate_mipmaps()
 var texture := ImageTexture.create_from_image(tile)
 var mat := ShaderMaterial.new()
 mat.shader = shader(filtered)
 mat.set_shader_parameter("source_texture", texture)
 mat.set_shader_parameter("tile_pixels", Vector2(tile.get_width(),tile.get_height()))
 mat.set_shader_parameter("metres_per_pixel", S)
 mat.set_shader_parameter("beam", role == "beam")
 mat.set_shader_parameter("world_origin",Vector3(-7.5,0,-5) if tiled else Vector3.ZERO)
 mat.set_meta("overhead_donor", donor)
 mat.set_meta("overhead_role", role)
 materials[key] = mat
 return mat

func tile_arrangement(tiles: Array) -> Image:
 var out := Image.create(600,400,false,Image.FORMAT_RGBA8)
 var sheets := {}
 for i in 96:
  var index := int(tiles[i])
  var sheet := int(index/128)+1
  var cell := index%128
  if not sheets.has(sheet):sheets[sheet]=world.sprite_image("assets/tiles/ts%02d.png" % sheet)
  out.blit_rect(sheets[sheet],Rect2i((cell%12)*50,int(cell/12)*50,50,50),Vector2i((i%12)*50,int(i/12)*50))
 return out

func reflected(crop: Image) -> Image:
 var w := crop.get_width()
 var h := crop.get_height()
 var out := Image.create(2*w,2*h,false,Image.FORMAT_RGBA8)
 for y in 2*h:
  for x in 2*w:
   out.set_pixel(x,y,crop.get_pixel(x if x<w else 2*w-1-x,y if y<h else 2*h-1-y))
 return out

func shader(filtered: bool) -> Shader:
 if shaders.has(filtered): return shaders[filtered]
 var value := Shader.new()
 # Axis-aligned box faces: select one orthogonal projection, never blend
 # normals or scale a crop to a face. Absolute coordinates keep phase across
 # beam segments. Every axis has exactly 1/S source pixels per metre.
 value.code = """shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D source_texture : source_color, repeat_enable, FILTER;
uniform vec2 tile_pixels;
uniform float metres_per_pixel;
uniform bool beam = false;
uniform bool provenance_tint = false;
uniform vec3 world_origin = vec3(0.0);
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
 vec3 n = abs(world_normal);
 vec3 p = world_position - world_origin;
 vec2 metres;
 if (n.y > 0.5) { metres = beam ? p.zx : p.xz; }
 else if (n.x > 0.5) { metres = p.zy; }
 else { metres = p.xy; }
 vec2 uv = metres / (metres_per_pixel * tile_pixels);
 ALBEDO = provenance_tint ? vec3(1.0,0.0,1.0) : texture(source_texture, uv).rgb;
 ROUGHNESS = 0.9;
}
""".replace("FILTER", "filter_linear_mipmap" if filtered else "filter_nearest_mipmap")
 shaders[filtered] = value
 return value
