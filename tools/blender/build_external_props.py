"""Turn approved Unity source meshes into Snowfield-ready runtime props.

The source FBX files, Unity materials and texture maps live under
``assets/source/external/mybros``.  They remain an editable, attributable
library.  Synty's native low-poly albedo maps are embedded in the generated
GLBs and used at runtime beneath the project's snow layer; normal, metallic
and roughness maps remain source provenance and are not sampled by the game.
"""

import math
import os

import bpy
from mathutils import Euler, Vector


ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE_ROOT = os.path.join(ROOT, "assets", "source", "external", "mybros")
OUTPUT_ROOT = os.path.join(ROOT, "assets", "models", "props")
BLEND_ROOT = os.path.join(ROOT, "assets", "source", "props")
# The cart is authored in this project and remains in the original small-prop
# tier.  Synty's Polygon sources are already deliberately low-poly, however:
# decimating their purposeful faceting turns barrels, tools and fence gaps into
# vague silhouettes.  Preserve those source meshes exactly; their individual
# and aggregate budgets are asserted in the Godot art gates instead.
MAX_RECONSTRUCTED_PROP_TRIANGLES = 200

# One albedo map per supplied Synty family.  The original Unity material files
# and their companion maps remain beside these files for source fidelity; the
# runtime uses only the albedo, which gives the props their authored painted
# detail without importing Unity's specular/PBR treatment into the snow scene.
SOURCE_ALBEDOS = {
    "generic": os.path.join(SOURCE_ROOT, "synty_polygon_generic", "textures", "alts", "Generic_01_A.png"),
    "military": os.path.join(SOURCE_ROOT, "synty_polygon_military", "textures", "alts", "PolygonMilitary_01_A.png"),
}


# ``sources`` entries are [source-relative path, Blender translation, Euler
# rotation]. Composite caches carry a story in one draw and one collider, so a
# player sees a readable place rather than a constellation of tiny objects.
SPECS = (
    {
        "file": "evacuation_cart",
        "mesh": "Evacuation_Cart",
        "slot": "PAL_STRUCT_2",
        "sources": (("horse_cart.fbx", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),),
    },
    {
        "file": "synty_supply_sacks",
        "mesh": "Synty_Supply_Sacks",
        "slot": "PAL_STRUCT_1",
        "sources": (("synty_polygon_generic/models/SM_Gen_Prop_Sack_Stack_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),),
    },
    {
        "file": "synty_wooden_barrel",
        "mesh": "Synty_Wooden_Barrel",
        "slot": "PAL_STRUCT_2",
        "sources": (("synty_polygon_generic/models/SM_Gen_Prop_Barrel_Wood_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),),
    },
    {
        "file": "synty_field_crate",
        "mesh": "Synty_Field_Crate",
        "slot": "PAL_STRUCT_2",
        "sources": (("synty_polygon_generic/models/SM_Gen_Prop_Crate_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),),
    },
    {
        "file": "synty_work_log",
        "mesh": "Synty_Work_Log",
        "slot": "PAL_STRUCT_3",
        "sources": (("synty_polygon_generic/models/SM_Gen_Env_Log_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),),
    },
    {
        "file": "synty_field_stump",
        "mesh": "Synty_Field_Stump",
        "slot": "PAL_STRUCT_3",
        "sources": (("synty_polygon_generic/models/SM_Gen_Env_Stump_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),),
    },
    {
        "file": "synty_pickaxe",
        "mesh": "Synty_Pickaxe",
        "slot": "PAL_STRUCT_3",
        "sources": (("synty_polygon_generic/models/SM_Gen_Wep_Pickaxe_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),),
    },
    {
        "file": "synty_yard_cache",
        "mesh": "Synty_Yard_Cache",
        "slot": "PAL_STRUCT_2",
        "sources": (
            ("synty_polygon_generic/models/SM_Gen_Prop_Crate_01.fbx", (-0.62, 0.0, -0.06), (0.0, 0.24, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Sack_Stack_01.fbx", (0.34, 0.0, 0.26), (0.0, -0.30, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Barrel_Wood_01.fbx", (0.65, 0.0, -0.49), (0.0, 0.10, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Wep_Pickaxe_01.fbx", (-0.55, 0.92, -0.23), (0.0, 0.0, 1.32)),
        ),
    },
    {
        "file": "synty_evacuation_cache",
        "mesh": "Synty_Evacuation_Cache",
        "slot": "PAL_STRUCT_1",
        "sources": (
            ("synty_polygon_generic/models/SM_Gen_Prop_Crate_01.fbx", (-0.48, 0.0, 0.38), (0.0, -0.22, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Sack_Stack_01.fbx", (0.40, 0.0, -0.16), (0.0, 0.40, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Env_Log_01.fbx", (0.02, 0.32, -0.68), (0.0, math.pi * 0.5, math.pi * 0.5)),
        ),
    },
    # A widened, readable work area costs one runtime draw rather than four.
    # The chopped log and axe make the firewood story legible before the player
    # reaches the farmhouse.
    {
        "file": "synty_woodwork_station",
        "mesh": "Synty_Woodwork_Station",
        "slot": "PAL_STRUCT_3",
        "sources": (
            ("synty_polygon_generic/models/SM_Gen_Prop_Barrel_Wood_02.fbx", (-0.78, 0.0, -0.24), (0.0, 0.28, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Env_Log_02.fbx", (0.46, 0.0, 0.32), (0.0, math.pi * 0.56, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Env_Stump_02.fbx", (-0.05, 0.0, -0.42), (0.0, -0.18, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Wep_Axe_01.fbx", (0.04, 0.74, -0.40), (0.0, 0.0, 1.08)),
        ),
    },
    # The larder is deliberately low and broad, so it reads as a searched
    # cache from the fixed isometric camera instead of another dark crate.
    {
        "file": "synty_larder_chest",
        "mesh": "Synty_Larder_Chest",
        "slot": "PAL_STRUCT_2",
        "sources": (
            ("synty_polygon_generic/models/SM_Gen_Prop_Chest_02.fbx", (0.0, 0.0, 0.0), (0.0, -0.24, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Crate_02.fbx", (-0.74, 0.0, 0.30), (0.0, 0.20, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Sack_03.fbx", (0.58, 0.0, 0.43), (0.0, -0.30, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Rope_01.fbx", (0.45, 0.08, -0.33), (0.0, 0.14, 0.0)),
        ),
    },
    # More provisions, but still one mesh and one palette surface at runtime.
    {
        "file": "synty_provision_stack",
        "mesh": "Synty_Provision_Stack",
        "slot": "PAL_STRUCT_1",
        "sources": (
            ("synty_polygon_generic/models/SM_Gen_Prop_Crate_03.fbx", (-0.54, 0.0, 0.10), (0.0, -0.12, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Barrel_Metal_02.fbx", (0.58, 0.0, -0.26), (0.0, 0.18, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Sack_Stack_02.fbx", (0.18, 0.0, 0.56), (0.0, -0.28, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Pot_02.fbx", (-0.54, 0.68, 0.10), (0.0, 0.10, 0.0)),
        ),
    },
    {
        "file": "synty_yard_table",
        "mesh": "Synty_Yard_Table",
        "slot": "PAL_STRUCT_2",
        "sources": (
            ("synty_polygon_generic/models/SM_Gen_Prop_Table_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.12, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Chair_01.fbx", (0.82, 0.0, 0.44), (0.0, math.pi * 1.10, 0.0)),
        ),
    },
    # A field cache from the military library, absorbed into the same winter
    # palette rather than carrying its original tactical colour treatment.
    {
        "file": "synty_tarped_cache",
        "mesh": "Synty_Tarped_Cache",
        "slot": "PAL_STRUCT_1",
        # The rope is a small tie-down detail on a military field cache. Give
        # the cluster its dominant military atlas too, so the whole composite
        # remains one material and one draw at runtime.
        "texture_family": "military",
        "sources": (
            ("synty_polygon_military/models/SM_Prop_Crate_Stack_Cover_02.fbx", (0.0, 0.0, 0.0), (0.0, -0.20, 0.0)),
            ("synty_polygon_military/models/SM_Prop_Sack_Large_01.fbx", (1.00, 0.0, 0.42), (0.0, 0.24, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Rope_02.fbx", (-0.30, 0.88, 0.08), (0.0, 0.0, 0.0)),
        ),
    },
    # A broken threshold marks that the road used to be an exit. Keeping both
    # fence pieces in one asset gives it one collider and one draw call.
    {
        "file": "synty_broken_gateway",
        "mesh": "Synty_Broken_Gateway",
        "slot": "PAL_STRUCT_3",
        "sources": (
            ("synty_polygon_military/models/SM_Prop_Fence_Damaged_02.fbx", (-1.42, 0.0, 0.0), (0.0, 0.0, 0.0)),
            ("synty_polygon_military/models/SM_Prop_Fence_Gate_01.fbx", (1.38, 0.0, -0.18), (0.0, 0.18, 0.0)),
        ),
    },
    {
        "file": "synty_firepit",
        "mesh": "Synty_Firepit",
        "slot": "PAL_STRUCT_3",
        "sources": (("synty_polygon_military/models/SM_Prop_FirePit_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),),
    },
    # ------------------------------------------------------------------
    # Second migration: the farm's survival traces, placed in depth bands
    # rather than scattered across the snow.  All retain native low-poly
    # planes and one sanitised source atlas below the common snow layer.
    {
        "file": "synty_generator_cache",
        "mesh": "Synty_Generator_Cache",
        "slot": "PAL_STRUCT_2",
        "texture_family": "military",
        "sources": (
            ("synty_polygon_military/models/SM_Prop_Generator_Small_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.12, 0.0)),
            ("synty_polygon_military/models/SM_Prop_GasCan_01.fbx", (0.80, 0.0, -0.36), (0.0, -0.18, 0.0)),
            ("synty_polygon_military/models/SM_Prop_AmmoBox_02.fbx", (-0.66, 0.0, 0.36), (0.0, 0.20, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Barrel_Metal_03.fbx", (0.58, 0.0, 0.48), (0.0, 0.28, 0.0)),
        ),
    },
    {
        "file": "synty_field_clinic",
        "mesh": "Synty_Field_Clinic",
        "slot": "PAL_STRUCT_1",
        "texture_family": "military",
        "sources": (
            ("synty_polygon_military/models/SM_Prop_Bed_Stretcher_01.fbx", (0.0, 0.0, 0.0), (0.0, math.pi * 0.5, 0.0)),
            ("synty_polygon_military/models/SM_Prop_MedicalBox_01.fbx", (-0.54, 0.0, 0.62), (0.0, 0.18, 0.0)),
            ("synty_polygon_military/models/SM_Prop_Sign_Medical_01.fbx", (0.78, 0.0, 0.46), (0.0, -0.28, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Sack_04.fbx", (-0.68, 0.0, -0.46), (0.0, 0.22, 0.0)),
        ),
    },
    {
        "file": "synty_fish_camp",
        "mesh": "Synty_Fish_Camp",
        "slot": "PAL_STRUCT_3",
        "texture_family": "military",
        "sources": (
            ("synty_polygon_military/models/SM_Prop_FirePit_Fish_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Pot_03.fbx", (0.72, 0.0, -0.34), (0.0, 0.18, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Bottle_01.fbx", (-0.54, 0.0, 0.46), (0.0, -0.20, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Prop_Rope_03.fbx", (0.12, 0.08, 0.68), (0.0, 0.0, 0.0)),
        ),
    },
    {
        "file": "synty_fuel_depot",
        "mesh": "Synty_Fuel_Depot",
        "slot": "PAL_STRUCT_2",
        "texture_family": "military",
        # Kept to the same readable footprint as the stranded flatbed; this is
        # an object-space scale only, so no native topology is removed.
        "runtime_scale": 0.90,
        "sources": (
            ("synty_polygon_military/models/SM_Prop_Pallet_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.10, 0.0)),
            ("synty_polygon_military/models/SM_Prop_BarrelPile_02.fbx", (-0.46, 0.0, 0.26), (0.0, -0.20, 0.0)),
            ("synty_polygon_military/models/SM_Prop_Fuel_Bladder_01.fbx", (0.70, 0.0, -0.32), (0.0, 0.24, 0.0)),
        ),
    },
    {
        "file": "synty_road_blockade",
        "mesh": "Synty_Road_Blockade",
        "slot": "PAL_STRUCT_3",
        "texture_family": "military",
        "sources": (
            ("synty_polygon_military/models/SM_Prop_Road_Barrier_01.fbx", (0.0, 0.0, 0.0), (0.0, math.pi * 0.5, 0.0)),
            ("synty_polygon_military/models/SM_Prop_Cone_01.fbx", (1.05, 0.0, 0.40), (0.0, 0.0, 0.0)),
            ("synty_polygon_military/models/SM_Prop_WireSpool_01.fbx", (-0.84, 0.0, -0.44), (0.0, 0.16, 0.0)),
        ),
    },
    {
        "file": "synty_radio_relay",
        "mesh": "Synty_Radio_Relay",
        "slot": "PAL_STRUCT_2",
        "texture_family": "military",
        "sources": (
            ("synty_polygon_military/models/SM_Prop_RadioPhone_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
            ("synty_polygon_military/models/SM_Prop_Radio_02.fbx", (0.54, 0.0, 0.42), (0.0, -0.22, 0.0)),
            ("synty_polygon_military/models/SM_Prop_Lamp_02.fbx", (-0.48, 0.0, 0.38), (0.0, 0.22, 0.0)),
            ("synty_polygon_military/models/SM_Prop_Crate_Wood_03.fbx", (0.06, 0.0, -0.54), (0.0, 0.12, 0.0)),
        ),
    },
    {
        "file": "synty_refuge_bedroll",
        "mesh": "Synty_Refuge_Bedroll",
        "slot": "PAL_STRUCT_1",
        "texture_family": "military",
        "sources": (
            ("synty_polygon_military/models/SM_Bld_Tent_Refugee_Damaged_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.16, 0.0)),
            ("synty_polygon_military/models/SM_Prop_Bed_SleepingBag_Roll_01.fbx", (1.10, 0.0, -0.60), (0.0, 0.26, 0.0)),
            ("synty_polygon_military/models/SM_Prop_Sack_06.fbx", (-0.92, 0.0, 0.62), (0.0, -0.20, 0.0)),
        ),
    },
    {
        "file": "synty_rock_cluster_north",
        "mesh": "Synty_Rock_Cluster_North",
        "slot": "PAL_STRUCT_3",
        "texture_family": "generic",
        "runtime_scale": 0.75,
        "sources": (
            ("synty_polygon_generic/models/SM_Gen_Env_Rock_01.fbx", (0.0, 0.0, 0.0), (0.0, 0.18, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Env_Rock_02.fbx", (1.04, 0.0, 0.28), (0.0, -0.22, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Env_Rock_03.fbx", (-0.78, 0.0, 0.66), (0.0, 0.32, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Env_Rock_Pebbles_01.fbx", (0.18, 0.0, -0.78), (0.0, 0.0, 0.0)),
        ),
    },
    {
        "file": "synty_rock_cluster_south",
        "mesh": "Synty_Rock_Cluster_South",
        "slot": "PAL_STRUCT_3",
        "texture_family": "generic",
        "sources": (
            ("synty_polygon_generic/models/SM_Gen_Env_Rock_04.fbx", (0.0, 0.0, 0.0), (0.0, -0.16, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Env_Rock_05.fbx", (0.90, 0.0, -0.42), (0.0, 0.22, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Env_Rock_06.fbx", (-0.76, 0.0, 0.58), (0.0, -0.30, 0.0)),
        ),
    },
    {
        "file": "synty_rock_cluster_east",
        "mesh": "Synty_Rock_Cluster_East",
        "slot": "PAL_STRUCT_3",
        "texture_family": "generic",
        "runtime_scale": 0.55,
        "sources": (
            ("synty_polygon_generic/models/SM_Gen_Env_Rock_07.fbx", (0.0, 0.0, 0.0), (0.0, 0.10, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Env_Rock_08.fbx", (1.10, 0.0, 0.30), (0.0, -0.24, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Env_Rock_09.fbx", (-0.82, 0.0, 0.58), (0.0, 0.28, 0.0)),
            ("synty_polygon_generic/models/SM_Gen_Env_Rock_10.fbx", (0.18, 0.0, -0.84), (0.0, -0.12, 0.0)),
        ),
    },
)


def _triangles(mesh) -> int:
    return sum(len(face.vertices) - 2 for face in mesh.polygons)


def _import(relative: str, location, rotation):
    source = os.path.join(SOURCE_ROOT, relative)
    if not os.path.isfile(source):
        raise SystemExit("build_external_props: missing approved source %s" % source)
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=source)
    meshes = [obj for obj in bpy.context.scene.objects if obj not in before and obj.type == "MESH"]
    if not meshes:
        raise SystemExit("build_external_props: no mesh in %s" % source)
    for obj in meshes:
        obj.location += Vector(location)
        obj.rotation_euler.rotate(Euler(rotation))
    return meshes


def _join(meshes, name: str):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def _palette_only(obj, slot: str) -> None:
    while len(obj.data.materials) > 0:
        obj.data.materials.pop(index=0)
    material = bpy.data.materials.new(slot)
    # Godot resolves the real palette colour by name. This viewport value is
    # deliberately unremarkable: it is never a runtime source of truth.
    material.diffuse_color = (0.08, 0.12, 0.20, 1.0)
    obj.data.materials.append(material)
    for face in obj.data.polygons:
        face.material_index = 0


def _native_material(family: str, slot: str):
    texture_path = SOURCE_ALBEDOS[family]
    if not os.path.isfile(texture_path):
        raise SystemExit("build_external_props: missing copied %s source albedo %s" % (family, texture_path))
    name = "SYNTY_TEX_%s_%s" % (family.upper(), slot)
    material = bpy.data.materials.get(name)
    if material is not None:
        return material
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    image_node = nodes.new("ShaderNodeTexImage")
    image_node.image = bpy.data.images.load(texture_path, check_existing=True)
    material.node_tree.links.new(image_node.outputs["Color"], shader.inputs["Base Color"])
    material.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return material


def _apply_native_material(meshes, family: str, slot: str) -> None:
    material = _native_material(family, slot)
    for obj in meshes:
        obj.data.materials.clear()
        obj.data.materials.append(material)
        for face in obj.data.polygons:
            face.material_index = 0


def _reduce_reconstructed_prop(obj, budget: int) -> tuple[int, int]:
    before = _triangles(obj.data)
    if before > budget:
        modifier = obj.modifiers.new("Establishing_Shot_Budget", "DECIMATE")
        modifier.ratio = min(1.0, (budget - 4) / float(before))
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    after = _triangles(obj.data)
    if after > budget:
        raise SystemExit("build_external_props: %s is %d triangles after reduction, over %d" % (obj.name, after, budget))
    return before, after


def _export(spec) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    meshes = []
    for relative, location, rotation in spec["sources"]:
        imported = _import(relative, location, rotation)
        texture_family = spec.get("texture_family", "")
        if texture_family != "":
            _apply_native_material(imported, texture_family, spec["slot"])
        elif relative.startswith("synty_polygon_generic/"):
            _apply_native_material(imported, "generic", spec["slot"])
        elif relative.startswith("synty_polygon_military/"):
            _apply_native_material(imported, "military", spec["slot"])
        meshes.extend(imported)
    obj = _join(meshes, spec["mesh"])
    runtime_scale = float(spec.get("runtime_scale", 1.0))
    if runtime_scale != 1.0:
        obj.scale = (runtime_scale, runtime_scale, runtime_scale)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    before = _triangles(obj.data)
    is_native_low_poly = all(relative.startswith("synty_polygon_") for relative, _, _ in spec["sources"])
    if is_native_low_poly:
        # See the user-approved source-quality rule above. A combine pass is
        # still a one-mesh, one-material, one-draw-call optimisation; it just
        # does not alter the source's authored planes.
        after = before
    else:
        _palette_only(obj, spec["slot"])
        before, after = _reduce_reconstructed_prop(obj, MAX_RECONSTRUCTED_PROP_TRIANGLES)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND_ROOT, spec["file"] + ".blend"))
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUTPUT_ROOT, spec["file"] + ".glb"),
        export_format="GLB",
        use_selection=True,
        export_materials="EXPORT",
        export_animations=False,
    )
    print("%s: source=%d triangles, runtime=%d triangles%s" % (
        spec["file"], before, after, " (native topology preserved)" if is_native_low_poly else ""
    ))


def main() -> None:
    for spec in SPECS:
        _export(spec)


main()
