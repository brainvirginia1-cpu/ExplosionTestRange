extends RefCounted

const Layout := preload("res://scripts/editor/range_layout.gd")

var point := Vector3.ZERO
var power := 100.0
var conditions := Vector4i.ZERO
var wind_direction := 0
var device := 0
var blast_mode := 0
var depth := 8.0
var seed := 4207
var hits: Array[Vector3] = []
var camera_view := Transform3D.IDENTITY
var configuration: Layout
