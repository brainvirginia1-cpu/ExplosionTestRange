extends Node3D

enum Kind { WALL, CONTAINER, SHELTER, DRUM, BRICK, PIPES, CRATES, TOWER, BARRIER, SIGN }

const NAMES := ["Панельная ограда", "Грузовой модуль", "Смотровой павильон", "Секционный бак",
	"Кладка с облицовкой", "Батарея резервуаров", "Штабель тары", "Рамная вышка", "Блочное ограждение", "Щит на стойках"]
const INTEGRITY := [0.76, 1.03, 1.24, 0.22, 0.79, 1.29, 0.51, 0.92, 1.43, 0.31]
# Gameplay fastenings for the modular props. Steel panels and concrete retain distinct strengths.
const FASTENING_SCALE := [0.54, 0.40, 0.34, 0.74, 0.45, 0.50, 0.62, 0.34, 0.57, 0.64]
const MASS := [8.2, 3.9, 5.7, 1.1, 4.1, 9.5, 1.4, 3.2, 11.4, 1.75]
const FRICTION := [0.88, 0.56, 0.71, 0.43, 0.86, 0.70, 0.66, 0.52, 0.91, 0.62]
const COLORS := [Color("#957d69"), Color("#a45f41"), Color("#858179"), Color("#a77836"),
	Color("#a74d36"), Color("#9f9480"), Color("#996834"), Color("#77756c"), Color("#958475"), Color("#494541")]
const DIMENSIONS := [Vector3(6.9, 2.7, 0.49), Vector3(5.91, 2.65, 2.5),
	Vector3(7.6, 3.5, 4.3), Vector3(0.71, 0.91, 0.71), Vector3(4.62, 2.22, 0.56),
	Vector3(3.78, 2.74, 1.89), Vector3(2.03, 1.80, 1.54), Vector3(1.87, 5.55, 1.87), Vector3(2.95, 0.96, 0.82), Vector3(1.02, 1.45, 0.64)]
const WEAR := preload("res://assets/shaders/target_wear.gdshader")
const IMPACT := preload("res://assets/sounds/range_impact.wav")
const AcousticEvent := preload("res://scripts/audio/acoustic_event.gd")
const LandingDust := preload("res://scripts/destruction/landing_dust.gd")

var kind: int = Kind.WALL
var sections: Array[RigidBody3D] = []
var fractured := false
var health := 1.0
var last_hit_radius := -1.0
var _body_material: PhysicsMaterial
var _ground_puffs := 0
var _fastening: Array[float] = []
var _support: Array[int] = []
var _rests_on_frame: Array[bool] = []
var _yielding_supports: Dictionary[int, float] = {}
var _support_pins: Dictionary[int, PinJoint3D] = {}
var _carried_sections: Dictionary[int, Transform3D] = {}
var _release: Array[float] = []
var _section_bounds: Array[AABB] = []
var _settling_contacts: Dictionary[Vector2i, float] = {}
var _elapsed := 0.0
var _source := Vector3.ZERO
var _push_strength := 0.0
static var meshes := {}
static var shapes := {}
static var finishes := {}

func _ready() -> void:
	health = INTEGRITY[kind]
	_body_material = PhysicsMaterial.new()
	_body_material.friction = FRICTION[kind]
	_body_material.bounce = 0.06
	_build()
	set_physics_process(false)

func _mesh(size: Vector3, tint: Color, round_part: bool) -> Mesh:
	var key := [size,tint,round_part]
	if meshes.has(key):
		return meshes[key]
	var mesh: PrimitiveMesh
	if round_part:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = size.x*0.5
		cylinder.bottom_radius = size.x*0.5
		cylinder.height = size.y
		cylinder.radial_segments = 16
		mesh = cylinder
	else:
		var box := BoxMesh.new()
		box.size = size
		mesh = box
	if not finishes.has(tint):
		var finish := StandardMaterial3D.new()
		finish.albedo_color = tint
		finish.roughness = 0.81
		finishes[tint] = finish
	mesh.material = finishes[tint]
	meshes[key] = mesh
	return mesh

func _detail(parent: Node3D, at: Vector3, size: Vector3, tint: Color, rounded := false) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = _mesh(size,tint,rounded)
	item.position = at
	parent.add_child(item)
	return item

func _part(at: Vector3, size: Vector3, strength: float, tint: Color, support := -1, rounded := false, rests_on_frame := false) -> int:
	var body := RigidBody3D.new()
	body.position = at
	body.freeze = true
	body.mass = maxf(0.25,float(MASS[kind])*size.x*size.y*size.z)
	body.physics_material_override = _body_material
	body.collision_layer = 2
	body.collision_mask = 3
	var collision_size := size*0.94
	_section_bounds.append(AABB(-collision_size*0.5,collision_size))
	var key := [collision_size,rounded]
	if not shapes.has(key):
		if rounded:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = collision_size.x*0.5
			cylinder.height = collision_size.y
			shapes[key] = cylinder
		else:
			var box := BoxShape3D.new()
			box.size = collision_size
			shapes[key] = box
	var hit := CollisionShape3D.new()
	hit.shape = shapes[key]
	body.add_child(hit)
	_detail(body,Vector3.ZERO,size,tint,rounded)
	add_child(body)
	sections.append(body)
	_support.append(support)
	_rests_on_frame.append(rests_on_frame)
	_fastening.append(strength*(0.94+0.12*fposmod(at.dot(Vector3(7.3,5.9,1.2)),1.0)))
	_release.append(-1)
	return sections.size()-1

func _build() -> void:
	var tint: Color = COLORS[kind]
	var steel := Color("#505e62")
	var timber := Color("#966943")
	var dims: Vector3 = DIMENSIONS[kind]
	match kind:
		Kind.WALL,Kind.BRICK,Kind.BARRIER:
			var cols := 7 if kind==Kind.BRICK else (5 if kind==Kind.WALL else 3)
			var rows := 5 if kind==Kind.BRICK else 3
			var cell := Vector3(dims.x/cols,dims.y/rows,dims.z)
			for y in rows:
				for x in cols:
					var loc := Vector3((x-(cols-1)*0.5)*cell.x,(y+0.5)*cell.y,0)
					var id := _part(loc,cell*0.986,2.7-1.65*y/maxi(1,rows-1)-0.20*absf(x-(cols-1)*0.5),tint.lightened(fposmod(x*0.27+y*0.31,0.16)),(y-1)*cols+x if y>0 else -1)
					for side: float in [-1.0,1.0]:
						_detail(sections[id],Vector3(0,0,side*cell.z*0.49),
							Vector3(cell.x*0.92,cell.y*0.83,0.030),tint)
					if kind == Kind.BARRIER and y == rows-1:
						_detail(sections[id],Vector3(0,0.02,cell.z*0.53),Vector3(cell.x*0.72,0.058,0.012),Color("#c69b49"))
					elif kind == Kind.BRICK:
						_detail(sections[id],Vector3(cell.x*(0.18 if (x+y)%2==0 else -0.18),0,cell.z*0.53),
							Vector3(0.018,cell.y*0.83,0.018),Color("#82674f"))
		Kind.CONTAINER,Kind.SHELTER:
			_build_building(dims,tint,steel)
		Kind.DRUM,Kind.PIPES:
			var count := 3 if kind==Kind.PIPES else 1
			for i in count:
				var last := -1
				var diam := 1.12 if count==3 else 0.71
				for band in 4:
					var loc := Vector3((i-1)*1.23 if count==3 else 0,(band+0.5)*dims.y/4,0)
					last = _part(loc,Vector3(diam,dims.y/4-0.009,diam),2.6-band*0.55,tint,last,true)
					_detail(sections[last],Vector3.UP*(dims.y/8-0.032),Vector3(diam*1.044,0.045,diam*1.044),steel,true)
					if band == 3:
						_detail(sections[last],Vector3(0.12,dims.y/8,0.07),Vector3(diam*0.23,0.065,diam*0.23),steel.lightened(0.21),true)
		Kind.CRATES:
			for stack in 2:
				var last := -1
				for y in 3:
					last = _part(Vector3(stack-0.5,0.30+y*0.60,0),Vector3(0.96,0.58,1.45),2.25-0.6*y,timber,last)
					for slat in 4:
						_detail(sections[last],Vector3((slat-1.5)*0.24,0,0.73),Vector3(0.21,0.56,0.04),timber.lightened(slat*0.045))
					_detail(sections[last],Vector3(0,0,0.77),Vector3(0.98,0.09,0.06),tint).rotation.z=0.43
		Kind.TOWER:
			_build_tower(dims,tint,steel)
		Kind.SIGN:
			for side: float in [-1.0,1.0]:
				var post := _part(Vector3(side*0.37,0.52,0),Vector3(0.11,1.04,0.12),2.35,steel)
				var panel := _part(Vector3(side*0.234,1.24,0),Vector3(0.452,0.39,0.075),0.92,tint,post,false,true)
				_detail(sections[panel],Vector3(0,0,0.049),Vector3(0.414,0.32,0.024),Color("#c3994c"))
				_detail(sections[panel],Vector3(0,0,0.066),Vector3(0.29,0.042,0.012),steel)

func _build_building(dims: Vector3, tint: Color, steel: Color) -> void:
	var shelter := kind == Kind.SHELTER
	var bay_width := dims.x/4.0
	var wall_z := dims.z*0.5-0.12
	var top := dims.y-0.22
	var floor_tint := Color("#78675a") if shelter else Color("#635849")
	for bay in 4:
		var bay_center := (bay-1.5)*bay_width
		var base := _part(Vector3(bay_center,0.10,0),Vector3(bay_width-0.045,0.20,dims.z-0.05),3.65,steel)
		for plank in 5:
			_detail(sections[base],Vector3(0,0.109,(plank-2)*dims.z*0.17),
				Vector3(bay_width-0.09,0.025,dims.z*0.157),floor_tint.lightened(0.03*plank))
		for side: float in [-1.0,1.0]:
			var z := side*wall_z
			var x := bay_center-bay_width*0.5+0.10
			var post := _part(Vector3(x,(top+0.23)*0.5,z),Vector3(0.135,top-0.23,0.145),2.58,steel,base)
			_detail(sections[post],Vector3(0,-top*0.36,0),Vector3(0.19,0.095,0.19),steel.lightened(0.12))
			if bay == 3:
				_part(Vector3(dims.x*0.5-0.10,(top+0.23)*0.5,z),Vector3(0.135,top-0.23,0.145),2.60,steel,base)
			var height := top-0.27
			if shelter and side > 0.0:
				height = 0.82 if bay != 1 else 0.0
			if height > 0.0:
				var panel_width := bay_width-0.39
				var panel := _part(Vector3(bay_center+0.025,0.23+height*0.5,z),
					Vector3(panel_width,height,0.090),1.04,tint.lightened((bay%2)*0.06),post)
				for rib in 5:
					var rib_x := (rib-2)*panel_width*0.18
					_detail(sections[panel],Vector3(rib_x,0,side*0.059),Vector3(0.048,height-0.06,0.057),tint.lightened(0.15))
				_detail(sections[panel],Vector3(0,height*0.47,side*0.064),Vector3(panel_width,0.069,0.045),steel)
			var roof_z := side*(dims.z*0.25+0.012)
			var roof_width := dims.z*0.5-0.036
			var roof := _part(Vector3(bay_center,top+0.095,roof_z),
				Vector3(bay_width-0.042,0.16,roof_width),1.40,steel.lightened(0.16),post,false,true)
			for ridge in 3:
				_detail(sections[roof],Vector3((ridge-1)*bay_width*0.26,0.092,0),
					Vector3(0.048,0.042,roof_width-0.03),steel.lightened(0.33))
			_detail(sections[roof],Vector3(0,-0.064,side*(roof_width*0.5-0.045)),
				Vector3(bay_width-0.05,0.17,0.075),tint)
		if bay != 0 and bay != 3:
			continue
		var end_x := (1.0 if bay==3 else -1.0)*(dims.x*0.5-0.04)
		for side: float in [-1.0,1.0]:
			var door_width := dims.z*0.5-0.26
			var door := _part(Vector3(end_x,(top+0.32)*0.5,side*(door_width*0.5+0.027)),
				Vector3(0.075,top-0.35,door_width),1.18,tint,base)
			var facing := signf(end_x)
			_detail(sections[door],Vector3(facing*0.056,0,0),Vector3(0.055,top-0.51,0.055),steel)
			_detail(sections[door],Vector3(facing*0.075,-0.19,side*0.12),Vector3(0.085,0.050,0.24),steel.lightened(0.20))

func _build_tower(dims: Vector3, tint: Color, steel: Color) -> void:
	var step := (dims.y-0.45)/4.0
	var radius := dims.x*0.41
	for side: float in [-1.0,1.0]:
		var front := -1
		var rear := -1
		for level in 4:
			var y := (level+0.5)*step
			front = _part(Vector3(side*radius,y,radius),Vector3(0.125,step-0.025,0.125),2.75-level*0.39,steel,front)
			rear = _part(Vector3(side*radius,y,-radius),Vector3(0.125,step-0.025,0.125),2.75-level*0.39,steel,rear)
			var brace := _part(Vector3(side*radius,y,0),Vector3(0.067,0.078,sqrt(pow(radius*2.0-0.22,2.0)+pow(step*0.73,2.0))),
				1.36,steel.lightened(0.15),front)
			sections[brace].rotation.x = (1.0 if level%2==0 else -1.0)*atan2(step*0.73,radius*2.0-0.22)
			if side < 0.0:
				for rung in 4:
					_detail(sections[front],Vector3(0.18,(rung-1.5)*step/4.0,0.091),Vector3(0.37,0.042,0.056),steel.lightened(0.22))
		var deck := _part(Vector3(side*dims.x*0.249,step*4.0+0.078,0),
			Vector3(dims.x*0.486,0.12,dims.z-0.035),1.21,tint,front,false,true)
		for strip in 4:
			_detail(sections[deck],Vector3(0,0.065,(strip-1.5)*dims.z*0.21),
				Vector3(dims.x*0.467,0.026,dims.z*0.19),tint.lightened(0.07+strip*0.02))
		_detail(sections[deck],Vector3(side*dims.x*0.224,0.33,0),Vector3(0.055,0.065,dims.z-0.12),Color("#d1a45a"))
		for end in [-1.0,1.0]:
			_detail(sections[deck],Vector3(side*dims.x*0.224,0.18,end*dims.z*0.43),
				Vector3(0.054,0.32,0.054),steel)


func receive_front(origin: Vector3, impact: float, distance: float, detailed: bool, distance_fraction := 0.0) -> int:
	if impact<=0 or last_hit_radius>=0:
		return 0
	last_hit_radius = distance
	health = maxf(0,health-impact)
	_source = origin
	_push_strength = clampf(impact, 0.1, 4.1)
	var count := 0
	var distance_blend := smoothstep(0.03,0.96,distance_fraction)
	var support_delay := lerpf(0.045,0.18,distance_blend)
	var frame_delay := lerpf(0.19,0.72,distance_blend)
	for i in sections.size():
		var parent := _support[i]
		var unsupported := parent>=0 and _release[parent]>=0
		var required := _fastening[i]*float(INTEGRITY[kind])*float(FASTENING_SCALE[kind])
		if parent < 0:
			required *= 0.72
		if impact < required and not unsupported:
			continue
		var structural := _fastening[i] >= 1.65 or parent < 0
		if impact < required or (_rests_on_frame[i] and unsupported):
			_release[i] = _release[parent]+support_delay
			if _rests_on_frame[i]:
				_carried_sections[i] = sections[parent].transform.affine_inverse()*sections[i].transform
				_pause_contact(i,parent)
		elif not structural and not _rests_on_frame[i]:
			_release[i] = 0.0
		else:
			_release[i] = frame_delay*(0.82+0.34*fposmod(i*0.618,1.0))
			if not _rests_on_frame[i]:
				_yielding_supports[i] = _release[i]*0.22
		count+=1
	if detailed and impact>0.15:
		var wear := ShaderMaterial.new()
		wear.shader = WEAR
		wear.set_shader_parameter("wear",clampf(impact/float(INTEGRITY[kind]),0.0,0.8))
		wear.set_shader_parameter("dust_tint",COLORS[kind].darkened(0.38))
		for section in sections:
			(section.get_child(1) as MeshInstance3D).material_overlay = wear
	if count>0:
		_allow_initial_separation()
		_physics_process(0.0)
		if detailed:
			_emit_gravel(0.5)
			_play_impact()
	return count

func _physics_process(delta: float) -> void:
	_elapsed += delta
	var pending := false
	var loose := 0
	for i in sections.size():
		if _release[i] < 0.0:
			continue
		var body := sections[i]
		if _carried_sections.has(i):
			body.transform = sections[_support[i]].transform*_carried_sections[i]
		if _elapsed < _release[i]:
			pending = true
			if _yielding_supports.has(i) and _elapsed >= _yielding_supports[i] and body.freeze:
				_tip_support(i)
			continue
		loose += 1
		if _support_pins.has(i):
			var pin := _support_pins[i]
			pin.node_a = NodePath()
			pin.node_b = NodePath()
			pin.queue_free()
			_support_pins.erase(i)
		if not body.freeze:
			continue
		_release_section(i)
	fractured = loose*2 >= sections.size()
	_restore_separated_contacts()
	set_physics_process(pending or not _settling_contacts.is_empty())

func _tip_support(index: int) -> void:
	var body := sections[index]
	var height := (body.get_child(1) as MeshInstance3D).get_aabb().size.y
	var pivot := body.global_position-Vector3.UP*height*0.46
	var parent := _support[index]
	var joint := PinJoint3D.new()
	joint.exclude_nodes_from_collision = false
	add_child(joint)
	joint.global_position = pivot
	joint.node_a = joint.get_path_to(body)
	if parent >= 0:
		joint.node_b = joint.get_path_to(sections[parent])
	_support_pins[index] = joint
	body.continuous_cd = true
	body.freeze = false
	body.sleeping = false
	var heading := (body.global_position-_source).slide(Vector3.UP).normalized()
	if heading.is_zero_approx():
		heading = global_basis.z
	# Push the upper part of the section while its foot is still attached.
	body.apply_impulse(heading * body.mass * clampf(_push_strength*0.45,0.42,1.45),
		Vector3.UP*height*0.38)
	_watch_landing(index)

func _release_section(index: int) -> void:
	var body := sections[index]
	body.continuous_cd = true
	var outward := (body.global_position-_source).slide(Vector3.UP)
	var angle := float(index)*2.39996+rotation.y
	var scatter := Vector3(cos(angle),0,sin(angle))
	var heading := (outward.normalized()+scatter*0.38).normalized()
	body.freeze = false
	body.sleeping = false
	if _release[index] == 0.0:
		var lift := 0.75+fposmod(index*0.73,0.9)
		body.linear_velocity = (heading*(2.4+fposmod(index*0.37,1.3))+Vector3.UP*lift)*_push_strength
		body.angular_velocity = (Vector3.UP.cross(heading)+scatter*0.32)*_push_strength
	elif _carried_sections.has(index):
		for neighbor in sections.size():
			if neighbor == index:
				continue
			var pair := Vector2i(mini(index,neighbor),maxi(index,neighbor))
			if not _overlap_offset(pair).is_zero_approx():
				_pause_contact(index,neighbor)
		var parent := sections[_support[index]]
		body.linear_velocity = parent.linear_velocity + parent.angular_velocity.cross(
			body.global_position-parent.global_position)
		body.angular_velocity = parent.angular_velocity
		_carried_sections.erase(index)
	else:
		body.linear_velocity = heading*0.25
		body.angular_velocity = Vector3.UP.cross(heading)*0.65
	_watch_landing(index)

func _pause_contact(first: int, second: int) -> void:
	var pair := Vector2i(mini(first,second),maxi(first,second))
	if not _settling_contacts.has(pair):
		sections[pair.x].add_collision_exception_with(sections[pair.y])
		_settling_contacts[pair] = 0.34

func _allow_initial_separation() -> void:
	for first in sections.size():
		for second in range(first+1,sections.size()):
			if _release[first] < 0.0 and _release[second] < 0.0:
				continue
			var pair := Vector2i(first,second)
			if not _overlap_offset(pair).is_zero_approx():
				_pause_contact(first,second)

func _overlap_offset(pair: Vector2i) -> Vector3:
	var first := sections[pair.x].transform
	var second := sections[pair.y].transform
	var box_a := _section_bounds[pair.x]
	var box_b := _section_bounds[pair.y]
	if not (first*box_a).intersects(second*box_b):
		return Vector3.ZERO
	var a := first.basis.orthonormalized()
	var b := second.basis.orthonormalized()
	var delta := first.origin-second.origin
	var axes := [a.x,a.y,a.z,b.x,b.y,b.z]
	for i in 3:
		for j in 3:
			axes.append(a[i].cross(b[j]))
	var half_a := box_a.size*0.5
	var half_b := box_b.size*0.5
	var shortest := INF
	var offset := Vector3.ZERO
	for candidate: Vector3 in axes:
		if candidate.length_squared()<0.00001:
			continue
		var axis := candidate.normalized()
		var radius_a := absf(axis.dot(a.x))*half_a.x + absf(axis.dot(a.y))*half_a.y + absf(axis.dot(a.z))*half_a.z
		var radius_b := absf(axis.dot(b.x))*half_b.x + absf(axis.dot(b.y))*half_b.y + absf(axis.dot(b.z))*half_b.z
		var projection := delta.dot(axis)
		var depth := radius_a+radius_b-absf(projection)
		if depth <= 0.004:
			return Vector3.ZERO
		if depth < shortest:
			shortest = depth
			offset = axis*depth*(-1.0 if projection < 0.0 else 1.0)
	return offset

func _restore_separated_contacts() -> void:
	for pair in _settling_contacts.keys():
		var first := sections[pair.x]
		var second := sections[pair.y]
		if _carried_sections.has(pair.x) or _carried_sections.has(pair.y):
			continue
		if _elapsed < _settling_contacts[pair] and not is_zero_approx(_elapsed):
			continue
		var overlap := _overlap_offset(pair)
		if overlap.is_zero_approx() or (first.freeze and second.freeze and _elapsed > maxf(_release[pair.x],_release[pair.y])):
			first.remove_collision_exception_with(second)
			_settling_contacts.erase(pair)
			continue
		_settling_contacts[pair] = _elapsed+0.075
		var first_loose := not first.freeze and not _support_pins.has(pair.x)
		var second_loose := not second.freeze and not _support_pins.has(pair.y)
		if not first_loose and not second_loose:
			continue
		var direction := (global_basis*overlap).normalized()
		if _elapsed > 1.15 and absf(direction.y) > 0.80:
			# Lift the upper fragment if the ground blocks separation below.
			first_loose = first_loose and direction.y > 0.0
			second_loose = second_loose and direction.y < 0.0
		var closing_speed := (first.linear_velocity-second.linear_velocity).dot(direction)
		if closing_speed >= 0.22:
			continue
		var speed := clampf(0.20+overlap.length()*6.5-closing_speed*0.4,0.22,2.6)
		if first_loose:
			first.apply_central_impulse(direction*speed*first.mass)
		if second_loose:
			second.apply_central_impulse(-direction*speed*second.mass)

func _watch_landing(index: int) -> void:
	if index%11 == 0:
		var body := sections[index]
		body.contact_monitor = true
		body.max_contacts_reported = 1
		body.body_entered.connect(_on_piece_contact.bind(body))

func _on_piece_contact(body: Node, piece: RigidBody3D) -> void:
	if _ground_puffs >= 2 or not body is StaticBody3D or body.collision_layer & 1 == 0:
		return
	_ground_puffs += 1
	_spawn_landing_dust.call_deferred(piece.global_position - Vector3.UP * 0.22)

func _spawn_landing_dust(at: Vector3) -> void:
	if not is_inside_tree():
		return
	_play_impact(to_local(at), -5.0)
	var dust := LandingDust.new()
	dust.position = to_local(at)
	dust.width = 1.15 if kind == Kind.DRUM or kind == Kind.SIGN else 1.80
	dust.variation = float(posmod(hash(at), 790)) * 0.018
	add_child(dust)

func _emit_gravel(amount: float = 1.0) -> void:
	if kind == Kind.DRUM:
		return
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.94
	particles.amount = roundi((48.0 if kind == Kind.BRICK or kind == Kind.CRATES else 36.0) * amount)
	particles.lifetime = 1.35
	particles.position.y = 0.8
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 84.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 7.0
	process.gravity = Vector3(0, -12, 0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(2.0, 0.45, 0.4)
	process.scale_min = 0.24
	process.scale_max = 1.2
	particles.process_material = process
	var stone := PrismMesh.new()
	stone.size = Vector3(0.23, 0.045, 0.08) if kind == Kind.CRATES or kind == Kind.TOWER else Vector3(0.14, 0.09, 0.11)
	var stone_material := StandardMaterial3D.new()
	stone_material.albedo_color = COLORS[kind]
	stone.material = stone_material
	particles.draw_pass_1 = stone
	add_child(particles)
	particles.finished.connect(particles.queue_free)
	particles.emitting = true

func _play_impact(at := Vector3.ZERO, gain_db := 0.0) -> void:
	var sound := AcousticEvent.new()
	sound.stream = IMPACT
	sound.auto_free_if_inaudible = true
	sound.unit_size = 17.0
	sound.max_distance = 155.0
	sound.position = at
	sound.volume_db = -11.0 + gain_db
	sound.pitch_scale = [0.78, 1.32, 0.89, 1.58, 0.86, 0.64, 1.21, 1.12, 0.72, 1.44][kind]
	add_child(sound)
	sound.finished.connect(sound.queue_free)
