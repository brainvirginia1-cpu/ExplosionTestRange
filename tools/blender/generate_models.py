"""Generate the original range props and editable Blender source."""
from pathlib import Path
import math

import bpy

PROJECT = Path(__file__).resolve().parents[2]
OUTPUT = PROJECT / "assets" / "models"
OUTPUT.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb, metallic=0.0, roughness=0.7):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1.0)
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = mat.diffuse_color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return mat


concrete = material("Sun-bleached concrete", (0.42, 0.37, 0.29))
dark = material("Graphite", (0.052, 0.065, 0.066), 0.45)
paint = material("Weathered vermilion", (0.44, 0.095, 0.038), 0.22)
cream = material("Ivory stencil", (0.78, 0.67, 0.47))
zinc = material("Zinc fastener", (0.22, 0.25, 0.23), 0.7, 0.36)
glass = material("Dark observation glass", (0.039, 0.09, 0.12), 0.56, 0.18)
gold = material("Safety yellow", (0.83, 0.41, 0.033), 0.22)


def finish(name, mat, bevel):
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    if bevel:
        modifier = obj.modifiers.new("Edge wear", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return obj


def box(name, location, dimensions, mat, bevel=0.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    bpy.context.object.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(name, mat, bevel)


def barrel(name, radius, height, z, mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius, depth=height, location=(0, 0, z))
    obj = finish(name, mat, 0.012)
    for polygon in obj.data.polygons:
        polygon.use_smooth = abs(polygon.normal.z) < 0.5
    return obj


def label(word, location, size, mat):
    bpy.ops.object.text_add(location=location, rotation=(math.pi / 2, 0, 0))
    obj = bpy.context.object
    obj.data.body = word
    obj.data.align_x = "CENTER"
    obj.data.size = size
    obj.data.extrude = 0.001
    bpy.ops.object.convert(target="MESH")
    return finish(word, mat, 0)


def build_asset(name, build, display_offset):
    previous = set(bpy.data.objects)
    build()
    objects = set(bpy.data.objects) - previous
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT / f"{name}.glb"), export_format="GLB", use_selection=True, export_apply=True)
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    for obj in objects:
        for owner in list(obj.users_collection):
            owner.objects.unlink(obj)
        collection.objects.link(obj)
        obj.location.x += display_offset


def charge():
    box("Base", (0, 0, 0.083), (0.83, 0.72, 0.165), dark)
    barrel("Outer housing", 0.31, 0.46, 0.35, paint)
    barrel("Lower ring", 0.335, 0.06, 0.15, zinc)
    barrel("Upper ring", 0.335, 0.06, 0.54, zinc)
    barrel("Instrument cap", 0.24, 0.12, 0.62, dark)
    box("Indicator", (0, 0, 0.69), (0.23, 0.05, 0.03), gold)
    for x in (-0.27, 0.27):
        for y in (-0.23, 0.23):
            box("Base fastener", (x, y, 0.175), (0.085, 0.08, 0.055), zinc)
    label("TR-01", (0, -0.314, 0.35), 0.115, cream)


def panel():
    box("Concrete slab", (0, 0, 0), (1.37, 0.46, 0.88), concrete, 0.055)
    box("Inset paint", (0, -0.231, -0.14), (1.26, 0.01, 0.16), paint, 0.005)
    for x in (-0.47, 0.47):
        box("Recess", (x, -0.235, 0.25), (0.073, 0.015, 0.068), dark, 0.007)


def shelter():
    box("Foundation", (0, 0, 0.11), (7.6, 4.3, 0.22), concrete)
    box("Field shelter", (0, 0, 1.67), (7.1, 3.65, 3.12), dark, 0.06)
    for n in range(24):
        x = (n - 11.5) * 0.288
        box("Cladding rib", (x, 1.85, 1.66), (0.10, 0.09, 2.89), zinc, 0.013)
    for x in (-2.55, 2.55):
        box("Window frame", (x, -1.84, 2.2), (1.57, 0.12, 0.78), zinc)
        box("Window", (x, -1.91, 2.2), (1.41, 0.05, 0.64), glass)
    box("Access door", (0, -1.85, 1.15), (1.16, 0.15, 2.12), paint)
    box("Handle", (0.43, -1.95, 1.23), (0.14, 0.08, 0.055), zinc)
    box("Roof", (0, 0, 3.31), (7.44, 4.11, 0.23), zinc)
    box("Sign backing", (0, -2.09, 3.3), (3.2, 0.08, 0.34), dark)
    label("RANGE  /  01", (0, -2.14, 3.22), 0.26, cream)
    box("Mast", (2.47, 0.8, 4.72), (0.075, 0.075, 2.9), zinc)
    box("Crossbar", (2.47, 0.8, 5.95), (1.18, 0.08, 0.075), zinc)


def marker():
    box("Foot", (0, 0, 0.105), (0.87, 0.62, 0.21), concrete)
    box("Post", (0, 0, 0.74), (0.085, 0.085, 1.4), zinc)
    box("Plate", (0, -0.07, 1.2), (1.0, 0.105, 0.45), dark)
    label("T E S T", (0, -0.13, 1.145), 0.20, gold)


def container():
    box("Chassis", (0, 0, 0.14), (5.9, 2.5, 0.28), dark)
    box("Shell", (0, 0, 1.35), (5.8, 2.28, 2.45), paint)
    for n in range(21):
        x = (n - 10) * 0.267
        for y in (-1.145, 1.145):
            box("Pressed steel rib", (x, y, 1.32), (0.09, 0.07, 2.32), paint, 0.011)
    for x in (-2.86, 2.86):
        for y in (-1.15, 1.15):
            box("Corner post", (x, y, 1.36), (0.15, 0.15, 2.49), zinc)
    for x in (-1.41, 1.41):
        box("Cargo door", (x, -1.19, 1.34), (2.77, 0.15, 2.36), paint)
        for dx in (-0.49, 0.49):
            box("Door rod", (x + dx, -1.28, 1.34), (0.045, 0.06, 2.17), zinc, 0.008)
    box("Roof", (0, 0, 2.58), (5.91, 2.47, 0.13), zinc)
    label("CARGO  /  07", (-0.88, -1.29, 1.73), 0.28, cream)


def steel_fragment():
    box("Bent cladding centre", (0, 0, 0), (1.86, 0.12, 1.22), paint)
    for x, angle in [(-0.97, -0.23), (0.97, 0.31)]:
        end = box("Bent edge", (x, 0.055, 0), (0.23, 0.12, 1.14), paint)
        end.rotation_euler.z = angle
    for x in (-0.6, -0.3, 0, 0.3, 0.6):
        box("Fold", (x, -0.065, 0), (0.066, 0.06, 1.11), zinc, 0.008)


def roof_fragment():
    box("Roof panel", (0, 0, 0), (2.04, 1.22, 0.16), zinc)
    for x in (-0.82, 0, 0.82):
        box("Purlin", (x, 0, -0.1), (0.09, 1.12, 0.14), dark)


def drum():
    barrel("Painted steel drum", 0.34, 0.88, 0.44, gold)
    for z in (0.07, 0.29, 0.58, 0.82):
        barrel("Pressed band", 0.355, 0.047, z, zinc)
    barrel("Lid", 0.333, 0.025, 0.891, dark)


def flight_prop(is_rocket):
    body = gold if is_rocket else paint
    barrel("Painted stylized shell", 0.39, 1.64, 0.16, body)
    barrel("Lighting collar", 0.41, 0.10, 0.71, cream)
    barrel("Rear guard", 0.37, 0.15, -0.69, dark)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.39, location=(0, 0, 0.96))
    bpy.context.object.scale.z = 0.85
    dome = finish("Painted nose", body, 0)
    for face in dome.data.polygons:
        face.use_smooth = True
    for i in range(4):
        angle = i * math.pi / 2.0
        px = math.cos(angle) * 0.43
        py = math.sin(angle) * 0.43
        panel_obj = box("Visual fin", (px, py, -0.42), (0.48, 0.085, 0.49), zinc, 0.036)
        panel_obj.rotation_euler.z = angle
    label("TR-03" if is_rocket else "TR-02", (0, -0.393, 0.18), 0.16, cream)


brick_red = material("Fired clay", (0.46, 0.15, 0.091), 0.0, 0.91)
brick_dark = material("Dark fired clay", (0.29, 0.091, 0.057), 0.0, 0.92)
mortar = material("Buff mortar", (0.47, 0.40, 0.31), 0.0, 0.90)
wood = material("Dry stained pine", (0.28, 0.15, 0.061), 0.0, 0.89)
wood_light = material("Exposed pine", (0.51, 0.32, 0.14), 0.0, 0.87)


def beam(name, first, second, width, mat):
    from mathutils import Vector
    a, b = Vector(first), Vector(second)
    obj = box(name, (a + b) * 0.5, (width, width, (b - a).length), mat, width * 0.10)
    obj.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    return obj


def brickwall():
    box("Mortar core", (0, 0, 1.09), (4.46, 0.31, 2.14), mortar, 0.024)
    for row in range(8):
        for i in range(9 - row % 2):
            x = (i - 4 + 0.5 * (row % 2)) * 0.495
            shade = brick_dark if (row * 7 + i) % 9 < 2 else brick_red
            box("Brick", (x, 0, 0.155 + row * 0.268), (0.477, 0.365, 0.249), shade, 0.017)
    box("Footing", (0, 0, 0.062), (4.59, 0.55, 0.123), concrete)


def brick_rubble():
    for i in range(4):
        obj = box("Broken brick", ((i % 2 - 0.5) * 0.29, 0.0, (i // 2 - 0.5) * 0.20),
                  (0.295 - i * 0.014, 0.245, 0.162), brick_dark if i == 0 else brick_red, 0.029)
        obj.rotation_euler.y = (i - 1.5) * 0.10
    box("Attached mortar", (-0.05, 0.0, -0.188), (0.49, 0.22, 0.052), mortar, 0.007)


def concrete_arc(name, center, radius, depth, start=0.0, span=math.tau, segments=36):
    vx, faces = [], []
    cx, cy, cz = center
    for i in range(segments + 1):
        angle = start + span * i / segments
        for r, y in ((radius, -depth/2), (radius - 0.16, -depth/2),
                     (radius, depth/2), (radius - 0.16, depth/2)):
            vx.append((cx + math.cos(angle) * r, cy + y, cz + math.sin(angle) * r))
    for i in range(segments):
        k = i * 4
        faces.extend([(k,k+4,k+6,k+2), (k+1,k+3,k+7,k+5), (k,k+1,k+5,k+4), (k+2,k+6,k+7,k+3)])
    end = segments * 4
    faces.extend([(0,2,3,1), (end,end+1,end+3,end+2)])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vx, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    finish(name, concrete, 0.033)


def pipes():
    for x in (-1.02, 1.02):
        concrete_arc("Concrete drain", (x, 0, 0.85), 0.85, 1.85)
    concrete_arc("Stacked drain", (0, -0.08, 2.0), 0.72, 1.72)
    for x in (-1.2, 1.2):
        box("Timber wedge", (x, -0.77, 0.083), (0.60, 0.18, 0.165), wood)


def pipe_fragment():
    concrete_arc("Split pipe arc", (0, 0, -0.47), 0.76, 0.92, 0.26, 2.55, 15)


def pallet():
    for x in (-0.8, 0, 0.8):
        box("Pallet runner", (x, 0, 0.072), (0.17, 1.53, 0.143), wood)
    for i in range(7):
        box("Pallet deck", (0, (i-3)*0.216, 0.18), (2.00, 0.19, 0.09), wood_light)
    for x, y, z in ((-0.46, 0, 0.61), (0.49, 0, 0.61), (0.15, -0.03, 1.38)):
        box("Crate core", (x, y, z), (0.87, 1.11, 0.74), wood, 0.025)
        for i in range(5):
            box("Crate card", (x + (i-2)*0.173, y-0.56, z), (0.155, 0.059, 0.68), wood_light, 0.012)
        for off in (-0.31, 0.31):
            box("Crate batten", (x, y-0.596, z+off), (0.94, 0.067, 0.083), wood, 0.011)
        beam("Crate brace", (x-0.34,y-0.63,z-0.27), (x+0.34,y-0.63,z+0.27), 0.09, wood)


def timber():
    box("Split plank", (0, 0, 0), (1.22, 0.19, 0.09), wood_light, 0.017)
    obj = box("Fractured end", (0.56, -0.016, 0.0), (0.21, 0.14, 0.075), wood, 0.014)
    obj.rotation_euler.z = 0.38
    for x in (-0.31, 0.26):
        box("Dark fastener", (x, 0, 0.05), (0.049, 0.039, 0.017), dark, 0.005)


def tower():
    for x in (-0.66,0.66):
        for y in (-0.66,0.66):
            box("Concrete base", (x,y,0.11), (0.54,0.54,0.21), concrete)
            beam("Main post", (x,y,0.19), (x*0.70,y*0.70,4.85), 0.10, zinc)
    for z in (0.42,1.84,3.30,4.82):
        v = 0.66 - z*0.039
        for side in (-1,1):
            beam("Beam", (-v,side*v,z), (v,side*v,z), 0.071, dark)
            beam("Beam", (side*v,-v,z), (side*v,v,z), 0.071, dark)
            if z < 4.7:
                beam("Diagonal", (side*v,-v,z), (side*(v-0.039),v-0.039,z+1.40), 0.065, zinc)
                beam("Diagonal", (-v,side*v,z), (v-0.039,side*(v-0.039),z+1.40), 0.065, zinc)
    box("Signal cabinet", (0,0,5.02), (1.28,0.72,0.51), paint, 0.05)
    box("Beacon", (0,0,5.42), (0.28,0.28,0.24), gold, 0.03)


def beam_fragment():
    beam("Bent post", (0,0,-0.88), (0.025,0,0.78), 0.092, zinc)
    beam("Bent brace", (-0.38,0,-0.67), (0.025,0,0.62), 0.065, dark)
    box("Bracket", (0.0,0.0,-0.42), (0.25,0.19,0.10), zinc)


def barrier():
    box("Concrete foot", (0,0,0.17), (2.93,0.81,0.34), concrete, 0.061)
    box("Tapered body", (0,0,0.49), (2.88,0.61,0.48), concrete, 0.085)
    box("Crest", (0,0,0.83), (2.84,0.32,0.25), concrete, 0.048)
    for i in range(5):
        tab = box("Safety stripe", ((i-2)*0.46,-0.307,0.516), (0.205,0.018,0.33), gold, 0.005)
        tab.rotation_euler.y = 0.38


def concrete_fragment():
    obj = box("Broken concrete", (0,0,0), (0.89,0.56,0.48), concrete, 0.10)
    obj.rotation_euler.y = 0.13
    beam("Exposed reinforcement", (-0.52,0.08,-0.055), (0.38,0.09,-0.055), 0.034, zinc)
    beam("Exposed reinforcement", (-0.35,-0.21,0.11), (0.50,-0.18,0.09), 0.027, zinc)


build_asset("charge", charge, -8)
build_asset("wall_panel", panel, -5)
build_asset("shelter", shelter, 0)
build_asset("range_sign", marker, 6)
build_asset("container", container, 13)
build_asset("steel_fragment", steel_fragment, 19)
build_asset("roof_fragment", roof_fragment, 22)
build_asset("drum", drum, 25)
build_asset("drop_device", lambda: flight_prop(False), 28)
build_asset("rocket_device", lambda: flight_prop(True), 31)
build_asset("brickwall", brickwall, 36)
build_asset("brick_rubble", brick_rubble, 41)
build_asset("pipes", pipes, 46)
build_asset("pipe_fragment", pipe_fragment, 51)
build_asset("pallet", pallet, 55)
build_asset("timber_fragment", timber, 59)
build_asset("signal_tower", tower, 62)
build_asset("beam_fragment", beam_fragment, 66)
build_asset("traffic_barrier", barrier, 70)
build_asset("concrete_fragment", concrete_fragment, 74)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(Path(__file__).with_name("range_props.blend")))
