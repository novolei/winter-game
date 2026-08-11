extends TestCase

## The art gates are only as real as this walker. If find_files() silently
## returned nothing, every gate would pass forever while inspecting zero
## assets. These tests put real files on disk and demand they be found.

const AssetScannerScript := preload("res://tests/framework/asset_scanner.gd")

const FIXTURE_ROOT := "user://scanner_fixture"

func _write(relative_path: String) -> void:
	var handle := FileAccess.open(FIXTURE_ROOT.path_join(relative_path), FileAccess.WRITE)
	handle.store_string("fixture")
	handle.close()

func before_each() -> void:
	var absolute := ProjectSettings.globalize_path(FIXTURE_ROOT)
	DirAccess.make_dir_recursive_absolute(absolute.path_join("nested"))
	_write("top.tres")
	_write("nested/deep.tres")
	_write("ignored.txt")

func after_each() -> void:
	var absolute := ProjectSettings.globalize_path(FIXTURE_ROOT)
	DirAccess.remove_absolute(absolute.path_join("nested/deep.tres"))
	DirAccess.remove_absolute(absolute.path_join("nested"))
	DirAccess.remove_absolute(absolute.path_join("top.tres"))
	DirAccess.remove_absolute(absolute.path_join("ignored.txt"))
	DirAccess.remove_absolute(absolute)

func test_finds_files_recursively() -> void:
	var found := AssetScannerScript.find_files(FIXTURE_ROOT, [".tres"] as Array[String])
	assert_eq(found.size(), 2, "should find top.tres and nested/deep.tres")

func test_filters_by_suffix() -> void:
	var found := AssetScannerScript.find_files(FIXTURE_ROOT, [".txt"] as Array[String])
	assert_eq(found.size(), 1, "should find only ignored.txt")

func test_missing_root_yields_empty_not_error() -> void:
	var found := AssetScannerScript.find_files("res://this_folder_does_not_exist", [".tres"] as Array[String])
	assert_eq(found.size(), 0, "a missing folder should yield an empty result, not an error")
