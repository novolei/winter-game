extends SceneTree

## Prints how big every model under assets/models actually is.
##
## Run:
##   godot --headless --path <project> --script res://tools/measure_model_scale.gd
##
## THE INSTRUMENT HALF OF THE SCALE GATE. `data/scale/*.tres` says how big each
## asset class is SUPPOSED to be, written from real-world sizes; this says what
## the files on disk measure. A person setting a new band compares the two lists.
##
## Deliberately not folded into `tools/generate_asset_scales.gd`. A generator
## that measured the models and wrote a band around whatever it found would
## accept a 15 mm wolf and report success doing it -- the expectation has to come
## from somewhere other than the thing it judges, which is the same rule CLAUDE.md
## states for the palette tests.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")
const AssetProbeScript := preload("res://tests/framework/asset_probe.gd")
const ScaleScript := preload("res://src/definitions/asset_scale.gd")

const MODEL_ROOT := "res://assets/models"
const BAND_ROOT := "res://data/scale"


func _initialize() -> void:
	var bands := _bands()
	print("%-56s %9s %9s %9s %9s %9s   %s" % ["model", "x", "y", "z", "longest", "mesh box", "band"])
	var paths := AssetScannerScript.find_files(MODEL_ROOT, AssetScannerScript.MESH_SUFFIXES)
	var sorted := Array(paths)
	sorted.sort()
	for path in sorted:
		var measured := AssetProbeScript.bounds(path)
		if measured["error"] != "":
			print("%-56s %s" % [path, measured["error"]])
			continue
		var size: Vector3 = measured["size"]
		if int(measured["meshes"]) == 0:
			print("%-56s %9s %9s %9s %9s   (no mesh)" % [path, "-", "-", "-", "-"])
			continue
		var longest := maxf(size.x, maxf(size.y, size.z))
		var band = _band_for(path, bands)
		var verdict := "unbanded"
		if band != null:
			verdict = "%s %.3f..%.3f" % [
				(band.covers as String).trim_prefix(BAND_ROOT), band.smallest_m, band.largest_m]
			if band.refusal(size) != "":
				verdict += "  <-- OUT OF BAND"
		var mesh_box: Vector3 = measured["mesh_size"]
		print("%-56s %9.4f %9.4f %9.4f %9.4f %9.4f   %s" % [
			path, size.x, size.y, size.z, longest,
			maxf(mesh_box.x, maxf(mesh_box.y, mesh_box.z)), verdict])
	quit()


func _bands() -> Array:
	var found: Array = []
	var dir := DirAccess.open(BAND_ROOT)
	if dir == null:
		return found
	for entry in dir.get_files():
		if not entry.ends_with(".tres"):
			continue
		var band = load(BAND_ROOT.path_join(entry))
		if band != null:
			found.append(band)
	return found


func _band_for(path: String, bands: Array):
	var best = null
	for band in bands:
		if not band.applies_to(path):
			continue
		if best == null or band.specificity() > best.specificity():
			best = band
	return best
