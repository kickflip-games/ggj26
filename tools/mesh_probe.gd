extends SceneTree

const EXTS := ["glb", "gltf"]
const SKIP_DIRS := {
    ".godot": true,
    ".import": true,
}

func _init() -> void:
    var root := ProjectSettings.globalize_path("res://")
    print("res:// -> %s" % root)
    if root == "":
        push_error("Project root not initialized. Run with your project set (e.g. --path /path/to/project).")
        quit()
        return
    var paths: Array[String] = []
    _scan_dir("res://", paths)
    paths.sort()

    print("Found %d mesh files" % paths.size())

    var failed: Array[String] = []
    for path in paths:
        print("Loading: %s" % path)
        var res = ResourceLoader.load(path)
        if res == null:
            failed.append(path)
            push_error("FAILED: %s" % path)

    if failed.is_empty():
        print("All glb/gltf files loaded successfully.")
    else:
        printerr("Failed %d file(s):" % failed.size())
        for path in failed:
            printerr("  " + path)

    quit()

func _scan_dir(path: String, paths: Array[String]) -> void:
    var dir := DirAccess.open(path)
    if dir == null:
        push_error("Could not open dir: %s" % path)
        return

    var err := dir.list_dir_begin()
    if err != OK:
        push_error("Could not list dir: %s (err %s)" % [path, err])
        return
    while true:
        var name := dir.get_next()
        if name == "":
            break

        if name.begins_with("."):
            continue

        if dir.current_is_dir():
            if SKIP_DIRS.has(name):
                continue
            _scan_dir(path.path_join(name), paths)
        else:
            var ext := name.get_extension().to_lower()
            if EXTS.has(ext):
                paths.append(path.path_join(name))

    dir.list_dir_end()
