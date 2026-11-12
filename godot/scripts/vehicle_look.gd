class_name VehicleLook
extends RefCounted
## v1.17.0: the finishing pass that makes every vehicle look real close up (the Bulldog, the WW2 fighter, the
## racing cars, the spaceship and the coaster train). Each vehicle is still built in code; this goes over its
## materials afterwards and gives each kind of surface what it has in real life:
##   paint    lacquer with a sharp highlight, a faint "orange peel" ripple and small changes in gloss; on the
##            aircraft and the ship the panel seams and rows of rivets (a pattern made here, in the part's own
##            axes so it moves with it)
##   metal    brushed or scratched metal (ambientCG Metal009 / Metal038), so it doesn't look like plastic
##   carbon   the racing car's dark parts: carbon-fibre weave under lacquer (ambientCG Fabric004)
##   rubber   tyres, seals and grips (ambientCG Rubber004)
##   leather  dark brown or black seats and padding in the cockpits (ambientCG Leather026)
##   glass    canopies, visors and screens: clearer and sharper reflections
## The photo textures are CC0 (public domain) from ambientCG.com, in assets/textures/veh_*.jpg.
## Materials are changed once and shared (a cache), so this adds no work per frame beyond the extra texture reads.

static var _tex := {}
static var _cache := {}          # original material -> finished material
static var _panels: Texture2D


static func _t(name: String) -> Texture2D:
	if not _tex.has(name):
		var p := "res://assets/textures/veh_%s.jpg" % name
		_tex[name] = load(p) if ResourceLoader.exists(p) else null
	return _tex[name]


## Panel seams and rivets as a normal map (assets/textures/veh_panels_nrm.png, made once by a script; v1.17.0):
## panels about 0.6 x 0.9 m, staggered like real skin panels, a row of rivets along each seam. 1024 px = 2.4 m.
static func panel_normals() -> Texture2D:
	if _panels == null and ResourceLoader.exists("res://assets/textures/veh_panels_nrm.png"):
		_panels = load("res://assets/textures/veh_panels_nrm.png")
	return _panels


## Goes over every mesh under root. kind: "aircraft", "car", "ship", "coaster".
static func apply(root: Node, kind: String) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.material_override != null:
			m.material_override = finish(m.material_override, kind)
		elif m.mesh != null:
			for s in m.mesh.get_surface_count():
				var sm := m.get_surface_override_material(s)
				if sm == null:
					sm = m.mesh.surface_get_material(s)
				if sm != null:
					m.set_surface_override_material(s, finish(sm, kind))


static func finish(mat: Material, kind: String) -> Material:
	var sm := mat as StandardMaterial3D
	if sm == null:
		return mat
	var key := "%d|%s" % [sm.get_instance_id(), kind]
	if _cache.has(key):
		return _cache[key]
	var out := _finish(sm, kind)
	_cache[key] = out
	_cache["%d|%s" % [out.get_instance_id(), kind]] = out   # already finished: leave it alone next time
	return out


static func _tri(m: StandardMaterial3D, scale_m: float) -> void:
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false     # in the part's own axes: the pattern moves with it
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / scale_m


static func _finish(src: StandardMaterial3D, kind: String) -> StandardMaterial3D:
	if src.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or src.emission_enabled:
		return src                    # lights, screens, glows: leave as they are
	if src.albedo_texture != null or src.normal_enabled or src.uv1_triplanar:
		return src                    # textured already (logos, instrument panels, labels)
	var m := src.duplicate() as StandardMaterial3D
	var c := m.albedo_color
	var lum := c.get_luminance()
	if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and lum < 0.3:
		return src                    # dark see-through: the propeller blur discs, shadows (left alone)
	if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and c.a < 0.7:
		# glass: clear, with a sharp, bright reflection of the sky
		m.roughness = minf(m.roughness, 0.03)
		m.metallic_specular = 1.0
		m.rim_enabled = false
		return m
	var painted := m.vertex_color_use_as_albedo or m.clearcoat_enabled
	if painted:
		m.clearcoat_enabled = true
		m.clearcoat = maxf(m.clearcoat, 0.75)
		m.clearcoat_roughness = 0.06 if kind != "coaster" else 0.12
		m.roughness_texture = _t("chipped_rgh")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		m.roughness = clampf(m.roughness * 1.5, 0.25, 0.6)
		m.normal_enabled = true
		if kind == "aircraft" or kind == "ship":
			m.normal_texture = panel_normals()
			m.normal_scale = 0.55
			_tri(m, 2.4)
		else:
			m.normal_texture = _t("chipped_nrm")   # a faint ripple in the lacquer
			m.normal_scale = 0.12
			_tri(m, 1.6)
		return m
	if m.metallic >= 0.5:
		var brushed := lum > 0.25
		m.normal_enabled = true
		m.normal_texture = _t("brushed_nrm" if brushed else "steel_nrm")
		m.normal_scale = 0.35
		m.roughness_texture = _t("brushed_rgh" if brushed else "steel_rgh")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		m.roughness = clampf(m.roughness * 1.6, 0.25, 0.8)
		_tri(m, 0.6)
		return m
	if lum < 0.05 and m.roughness >= 0.75:
		# rubber: tyres, seals, grips, gaskets
		m.albedo_texture = _t("rubber_col")
		m.albedo_color = Color(c.r * 3.0 + 0.25, c.g * 3.0 + 0.25, c.b * 3.0 + 0.25)
		m.normal_enabled = true
		m.normal_texture = _t("rubber_nrm")
		m.normal_scale = 0.6
		m.roughness = 0.85
		_tri(m, 0.35)
		return m
	if lum < 0.06 and m.roughness < 0.5 and kind == "car":
		# the racing car's dark, glossy parts: carbon-fibre weave under lacquer
		m.albedo_texture = _t("carbon_col")
		m.albedo_color = Color(0.55, 0.55, 0.6)
		m.normal_enabled = true
		m.normal_texture = _t("carbon_nrm")
		m.normal_scale = 0.4
		m.roughness = 0.35
		m.metallic = 0.15
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.05
		_tri(m, 0.12)
		return m
	if (kind == "aircraft" or kind == "ship" or kind == "coaster") and lum > 0.01 and lum < 0.14 and m.roughness >= 0.6 and c.r >= c.b:
		# seats and padding: leather
		m.albedo_texture = _t("leather_col")
		m.albedo_color = Color(c.r * 2.2 + 0.1, c.g * 2.2 + 0.1, c.b * 2.2 + 0.1)
		m.normal_enabled = true
		m.normal_texture = _t("leather_nrm")
		m.normal_scale = 0.5
		m.roughness = 0.6
		_tri(m, 0.25)
		return m
	# everything else (plastic, painted metal, fabric): small changes in gloss and a faint grain
	m.roughness_texture = _t("chipped_rgh")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	m.roughness = clampf(m.roughness * 1.3, 0.2, 1.0)
	m.normal_enabled = true
	m.normal_texture = _t("chipped_nrm")
	m.normal_scale = 0.15
	_tri(m, 1.2)
	return m
