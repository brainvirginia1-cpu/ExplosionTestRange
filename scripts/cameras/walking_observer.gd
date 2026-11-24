extends CharacterBody3D

const Controls := preload("res://scripts/core/control_bindings.gd")
const Ground := preload("res://scripts/terrain/range_ground.gd")
const Device := preload("res://scripts/devices/trial_device.gd")
const EYE_HEIGHT := 1.65
const MAX_HEALTH := 100.0
var health := MAX_HEALTH
var third_person := false
var spawn_point := Vector3.ZERO
var _avatar := Node3D.new()
var _limbs: Array[Node3D] = []
var _stride := 0.0
var _lower_limbs: Array[Node3D] = []
var _region_wear: Array[ShaderMaterial] = []
var _injuries := PackedFloat32Array([0,0,0,0,0,0])
var _gait := 0.0
var _landing := 0.0
var _eye_offset := 0.0
const WEAR := preload("res://assets/shaders/observer_wear.gdshader")
var _contact_cooldown := 0.0
var camera: Camera3D
var shock_velocity := Vector3.ZERO
var burn_damage := 0.0
var limb_lost := false
var _ragdoll := Node3D.new()
var _torso: RigidBody3D
var _detachable_limbs: Array[RigidBody3D] = []
var _detachable_joints: Array[ConeTwistJoint3D] = []
var _down_time := 0.0
var _jump_held := false
var _reaction_time := 0.0
var _reaction_label := ""
var _brace := 0.0
var glare := 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 3
	floor_snap_length = 0.30
	max_slides = 5
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.78
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = capsule.height * 0.5
	add_child(collider)
	add_child(_avatar)
	add_child(_ragdoll)
	_build_avatar()
	_avatar.hide()
	set_physics_process(false)

func enter(terrain: Ground) -> void:
	var spawn := camera.global_position
	var limit := Ground.HALF_EXTENT - 2.0
	spawn.x = clampf(spawn.x,-limit,limit)
	spawn.z = clampf(spawn.z,-limit,limit)
	spawn.y = terrain.height_at(spawn.x,spawn.z) + 0.15
	if health > 0.0 and not is_instance_valid(_torso):
		spawn_point = spawn
		global_position = spawn
	velocity = Vector3.ZERO
	shock_velocity = Vector3.ZERO
	_follow()
	set_physics_process(true)

func leave() -> void:
	set_physics_process(false)
	_avatar.hide()

func _physics_process(delta: float) -> void:
	_reaction_time = maxf(0.0,_reaction_time-delta)
	_brace = move_toward(_brace,0.0,delta*1.40)
	glare = move_toward(glare,0.0,delta*0.46)
	if is_instance_valid(_torso):
		_down_time += delta
		if health > 0.0 and not limb_lost and _down_time > 2.0 and _torso.linear_velocity.length() < 1.6:
			global_position = _torso.global_position - Vector3.UP*0.05
			_clear_ragdoll()
		_follow()
		return
	var direction := Vector2.ZERO
	var sprint := false
	var jump := false
	if health > 0.0 and get_window().has_focus():
		direction = Vector2(
			float(Controls.pressed("right")) - float(Controls.pressed("left")),
			float(Controls.pressed("backward")) - float(Controls.pressed("forward")))
		sprint = Controls.pressed("sprint")
		jump = Controls.pressed("jump")
	var heading := Basis(Vector3.UP,camera.rotation.y)
	var leg_damage := maxf(_injuries[2],_injuries[4])
	var travel := heading * Vector3(direction.x,0,direction.y).normalized() * (7.2 if sprint else 3.8)
	travel *= lerpf(1.0,0.49,leg_damage)*(1.0-0.52*_brace)
	velocity.x = travel.x + shock_velocity.x
	velocity.z = travel.z + shock_velocity.z
	if jump and not _jump_held and is_on_floor() and _brace < 0.55:
		velocity.y = lerpf(4.5,2.4,leg_damage)
	_jump_held = jump
	var landing_speed := -velocity.y
	velocity.y -= 12.0 * delta
	var airborne := not is_on_floor()
	move_and_slide()
	if airborne and is_on_floor():
		_landing = minf(1.0,landing_speed/12.0)
		if landing_speed > 8.0:
			var damage := (landing_speed-8.0)*6.0
			_injure(2,damage*0.012)
			_injure(4,damage*0.009)
			hurt(damage)
	_contact_cooldown = maxf(0.0,_contact_cooldown-delta)
	if _contact_cooldown == 0.0 and health > 0.0:
		for i in get_slide_collision_count():
			var piece := get_slide_collision(i).get_collider() as RigidBody3D
			if piece != null and not piece.freeze and piece.linear_velocity.length() >= 3.0:
				var hit := to_local(get_slide_collision(i).get_position())
				var on_left := camera.global_basis.x.dot(hit) < 0.0
				var region := 2 if on_left else 4
				if hit.y > 1.55:
					region = 1
				elif hit.y > 1.02:
					region = 3 if on_left else 5
				var damage := minf(45.0,piece.linear_velocity.length()*3.0)
				_injure(region,damage*0.024)
				hurt(damage)
				_contact_cooldown = 0.45
				break
	_animate(delta,travel.length(),sprint)
	shock_velocity = shock_velocity.move_toward(Vector3.ZERO,delta * 7.0)
	var limit := Ground.HALF_EXTENT - 1.0
	position.x = clampf(position.x,-limit,limit)
	position.z = clampf(position.z,-limit,limit)
	_follow()

func _animate(delta: float, pace: float, sprint: bool) -> void:
	var grounded := is_on_floor()
	_gait = move_toward(_gait,minf(1.0,pace/3.8) if grounded else 0.0,delta*6.0)
	_stride = fposmod(_stride+pace*delta*(2.05 if sprint else 2.85),TAU)
	_landing = move_toward(_landing,0.0,delta*3.1)
	var target_bob := (absf(sin(_stride))*0.043*_gait)-_landing*0.14-_brace*0.12
	_eye_offset = lerpf(_eye_offset,target_bob,minf(1.0,delta*12.0))
	_avatar.position.y = _eye_offset
	_avatar.rotation.x = lerpf(_avatar.rotation.x,(-0.18 if sprint else -0.06)*_gait+0.26*_landing+0.22*_brace,minf(1.0,delta*10.0))
	for index in _limbs.size():
		var arm := index%2 == 1
		var phase := _stride + (0.0 if index == 0 or index == 3 else PI)
		var range_factor := lerpf(1.0,0.44,_injuries[index+2])
		var swing := sin(phase)*(0.77 if sprint else 0.48)*range_factor*_gait
		var bend := maxf(0.0,sin(phase+0.52))*0.96*range_factor*_gait
		if arm:
			bend = -0.12-bend*0.66-0.90*_brace
			swing -= _brace*0.62
		elif not grounded:
			bend = 0.36
		else:
			bend += 0.24*_brace
		var response := minf(1.0,delta*14.0)
		_limbs[index].rotation.x = lerpf(_limbs[index].rotation.x,swing,response)
		_lower_limbs[index].rotation.x = lerpf(_lower_limbs[index].rotation.x,bend,response)

func _injure(region: int, severity: float) -> void:
	_injuries[region] = clampf(_injuries[region]+severity,0.0,1.0)
	_region_wear[region].set_shader_parameter("abrasion",_injuries[region])

func hurt(amount: float) -> void:
	health = maxf(0.0,health-amount)
	if health == 0.0:
		_knock_down(velocity*0.45,false)

func heat_burn(amount: float) -> void:
	burn_damage += amount
	for i in _region_wear.size():
		var exposure := 1.0 if i <= 1 else 0.56
		_region_wear[i].set_shader_parameter("scorch",clampf(burn_damage/28.0*exposure,0.0,1.0))
	hurt(amount)

func strike(amount: float, impulse: Vector3, severe: bool) -> void:
	var local_hit := _avatar.global_basis.inverse()*impulse
	_injure(0,amount*0.008)
	_injure(3 if local_hit.x > 0.0 else 5,amount*0.016)
	_injure(2 if local_hit.x > 0.0 else 4,amount*0.010)
	if amount > 32.0:
		_injure(1,amount*0.005)
	health = maxf(0.0,health-amount)
	if amount >= 19.0 or health == 0.0:
		_knock_down(impulse,severe)
	else:
		shock_velocity = impulse

func react_to_blast(mode: int, direction: Vector3, strength: float, contact: float,
		growth: float, severe: bool, exposed: bool) -> void:
	if health <= 0.0 or strength <= 0.0:
		return
	match mode:
		Device.BlastMode.THERMOBARIC:
			_react("Жар и вспышка" if exposed else "Боковой удар",1.7,0.58*strength)
			if exposed:
				heat_burn((7.0+17.0*contact)*strength)
				glare = 0.32*strength
			strike(35.0*strength*strength+56.0*contact,direction*(4.3*strength+6.0*contact),severe)
		Device.BlastMode.UNDERGROUND:
			_react("Толчок из-под ног",1.6,0.64*strength)
			var impulse := direction*2.9*strength+Vector3.UP*4.0*strength
			strike(39.0*strength*strength,impulse,false)
			if not is_instance_valid(_torso):
				velocity.y = maxf(velocity.y,impulse.y)
		_:
			_react("Ударная волна",1.3,0.43*strength)
			var damage := strength*strength*lerpf(65.0,220.0,growth)+105.0*contact
			var impulse := direction*(6.4*strength+13.0*contact)+Vector3.UP*4.5*contact
			strike(damage,impulse,severe)

func react_to_ground(strength: float, settling: bool, downhill: Vector3) -> void:
	if health <= 0.0 or strength <= 0.0:
		return
	_react("Теряет опору" if settling else "Грунт подбрасывает",2.1,strength*0.85)
	_injure(2,0.23*strength)
	_injure(4,0.23*strength)
	var impulse := downhill*1.9*strength+Vector3.UP*strength*(-0.8 if settling else 1.8)
	if strength > 0.61:
		hurt(10.0*strength)
		_knock_down(impulse,false)
	else:
		shock_velocity = impulse

func _react(label: String, seconds: float, brace: float) -> void:
	_reaction_label = label
	_reaction_time = seconds
	_brace = maxf(_brace,brace)

func reaction_text() -> String:
	return _reaction_label if _reaction_time > 0.0 and health > 0.0 else ""

func _knock_down(impulse: Vector3, severe: bool) -> void:
	if is_instance_valid(_torso):
		_torso.apply_central_impulse(impulse*_torso.mass)
		if severe and not limb_lost:
			_detach_limbs(impulse)
		return
	_down_time = 0.0
	_avatar.rotation = Vector3(0,camera.rotation.y,0)
	var torso_mesh := _avatar.get_child(0) as MeshInstance3D
	_torso = _ragdoll_part(torso_mesh,impulse,12.0)
	var head := _avatar.get_child(1) as MeshInstance3D
	_join_ragdoll(_torso,_ragdoll_part(head,impulse,3.5),_avatar.to_global(Vector3.UP*1.53),30.0,37.0)
	for index in _limbs.size():
		var mount := _limbs[index]
		var segment := _ragdoll_part(mount.get_child(0),impulse,3.5 if index%2 == 0 else 2.0)
		var joint := _join_ragdoll(_torso,segment,mount.global_position,36.0 if index%2 == 0 else 61.0,23.0)
		var lower := _lower_limbs[index]
		var foresegment := _ragdoll_part(lower.get_child(0),impulse,1.4)
		_join_hinge(segment,foresegment,lower.global_transform,index%2 == 1,lower.rotation.x)
		if index == 1 or index == 2:
			_detachable_limbs.append(segment)
			_detachable_joints.append(joint)
	if severe:
		_detach_limbs(impulse)
	_avatar.hide()

func _join_ragdoll(parent: RigidBody3D, segment: RigidBody3D, anchor: Vector3, swing: float, twist: float) -> ConeTwistJoint3D:
	var joint := ConeTwistJoint3D.new()
	joint.swing_span = swing
	joint.twist_span = twist
	joint.exclude_nodes_from_collision = false
	_ragdoll.add_child(joint)
	joint.global_position = anchor
	joint.node_a = joint.get_path_to(parent)
	joint.node_b = joint.get_path_to(segment)
	return joint

func _join_hinge(upper: RigidBody3D, lower: RigidBody3D, pose: Transform3D,
		arm: bool, bend: float) -> void:
	var joint := HingeJoint3D.new()
	_ragdoll.add_child(joint)
	# Godot hinges rotate around local Z. Align Z with the character's lateral axis.
	joint.global_transform = Transform3D(Basis(pose.basis.y,pose.basis.z,pose.basis.x),pose.origin)
	# Hinge limits use the rotation of the first body relative to the second.
	var minimum := -deg_to_rad(132.0) if arm else 0.0
	var maximum := 0.0 if arm else deg_to_rad(128.0)
	joint.set("angular_limit/enable",true)
	joint.set("angular_limit/lower",bend-maximum)
	joint.set("angular_limit/upper",bend-minimum)
	joint.exclude_nodes_from_collision = false
	joint.node_a = joint.get_path_to(upper)
	joint.node_b = joint.get_path_to(lower)

func _detach_limbs(impulse: Vector3) -> void:
	limb_lost = true
	for index in _detachable_limbs.size():
		var joint := _detachable_joints[index]
		joint.node_b = NodePath()
		joint.queue_free()
		var limb := _detachable_limbs[index]
		var outward := (limb.global_position-_torso.global_position).normalized()
		limb.apply_central_impulse((outward*7.0 + impulse*0.22)*limb.mass)
		limb.apply_torque_impulse(Vector3(1.2,1.8,2.5)*limb.mass)
	_detachable_limbs.clear()
	_detachable_joints.clear()

func _ragdoll_part(source: MeshInstance3D, impulse: Vector3, weight: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = weight
	body.collision_layer = 4
	body.collision_mask = 7
	body.continuous_cd = true
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = source.mesh.get_aabb().size
	collider.shape = shape
	body.add_child(collider)
	var visual := source.duplicate() as MeshInstance3D
	visual.transform = Transform3D.IDENTITY
	body.add_child(visual)
	_ragdoll.add_child(body)
	body.global_transform = source.global_transform
	body.linear_velocity = impulse+Vector3.UP*0.9
	body.angular_velocity = Vector3(impulse.z,1.0,-impulse.x)*0.85
	return body

func _clear_ragdoll() -> void:
	for part in _ragdoll.get_children():
		part.queue_free()
	_torso = null
	_detachable_joints.clear()
	_detachable_limbs.clear()
	velocity = Vector3.ZERO

func body_position() -> Vector3:
	return _torso.global_position if is_instance_valid(_torso) else global_position+Vector3.UP*0.9

func region_damage(region: int) -> float:
	return _injuries[region]

func region_missing(region: int) -> bool:
	return limb_lost and (region == 3 or region == 4)

func injury_text() -> String:
	if limb_lost:
		return "Тяжёлая травма"
	if is_instance_valid(_torso):
		return "Сбит с ног"
	if maxf(_injuries[2],_injuries[4]) > 0.41:
		return "Травма ноги"
	if maxf(_injuries[3],_injuries[5]) > 0.41:
		return "Травма руки"
	return "Ожоги" if burn_damage > 0.0 else ""

func respawn(terrain: Ground) -> void:
	reset_injuries()
	var floor_height := terrain.height_at(spawn_point.x,spawn_point.z)
	global_position = Vector3(spawn_point.x,floor_height+0.15,spawn_point.z)
	velocity = Vector3.ZERO
	shock_velocity = Vector3.ZERO
	_contact_cooldown = 0.0
	_follow()

func reset_injuries() -> void:
	_clear_ragdoll()
	health = MAX_HEALTH
	burn_damage = 0.0
	_injuries.fill(0.0)
	_reaction_time = 0.0
	_reaction_label = ""
	_brace = 0.0
	glare = 0.0
	for wear in _region_wear:
		wear.set_shader_parameter("abrasion",0.0)
		wear.set_shader_parameter("scorch",0.0)
	limb_lost = false
	_contact_cooldown = 0.0
	shock_velocity = Vector3.ZERO

func _follow() -> void:
	var down := is_instance_valid(_torso)
	_avatar.visible = third_person and not down
	_avatar.rotation.y = camera.rotation.y
	var eye := _torso.global_position+Vector3.UP*0.35 if down else global_position+Vector3.UP*(EYE_HEIGHT+_eye_offset)
	camera.global_position = eye
	if third_person or down:
		var offset := camera.global_basis.z * 3.6
		var ray := PhysicsRayQueryParameters3D.create(eye,eye+offset,3)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			offset = offset.normalized()*maxf(0.0,eye.distance_to(hit.position)-0.19)
		camera.global_position += offset

func _build_avatar() -> void:
	var fabric := Color("#515b62")
	var orange := Color("#d79a46")
	var dark := Color("#263136")
	var reflective := Color("#ded7af")
	var torso := _part(_avatar,Vector3(0,1.29,0),Vector3(0.43,0.46,0.26),fabric,true)
	var helmet := _part(_avatar,Vector3(0,1.69,0),Vector3(0.25,0.26,0.25),orange,true)
	_part(helmet,Vector3(0,-0.035,-0.103),Vector3(0.19,0.074,0.068),Color("#314d5c"),true)
	for side in [-1.0,1.0]:
		_part(helmet,Vector3(side*0.112,-0.025,0.012),Vector3(0.042,0.10,0.092),dark,true)
	_part(helmet,Vector3(0,-0.106,-0.067),Vector3(0.14,0.06,0.105),dark,true)
	_part(torso,Vector3(0,0,-0.071),Vector3(0.40,0.41,0.155),orange,true)
	_part(torso,Vector3(0,-0.155,-0.117),Vector3(0.335,0.049,0.055),reflective)
	_part(torso,Vector3(0,0.018,0.11),Vector3(0.33,0.38,0.16),dark,true)
	_part(torso,Vector3(0,0.08,0.188),Vector3(0.26,0.17,0.028),fabric,true)
	_part(torso,Vector3(0,-0.249,0),Vector3(0.38,0.16,0.23),dark,true)
	_part(torso,Vector3(0,0.242,0),Vector3(0.16,0.13,0.16),dark,true)
	_part(torso,Vector3(0,0.028,0.203),Vector3(0.22,0.022,0.015),reflective)
	_part(torso,Vector3(0.133,0.105,0.197),Vector3(0.044,0.12,0.039),dark)
	_part(torso,Vector3(0.133,0.205,0.197),Vector3(0.012,0.11,0.013),dark)
	_part(helmet,Vector3(0,0.021,-0.094),Vector3(0.218,0.022,0.137),dark,true)
	_part(helmet,Vector3(0,0.111,0.005),Vector3(0.043,0.02,0.18),reflective,true)
	_part(torso,Vector3(0,-0.192,-0.141),Vector3(0.14,0.075,0.073),dark,true)
	_part(torso,Vector3(0,-0.227,0),Vector3(0.368,0.04,0.246),fabric)
	_part(torso,Vector3(0,-0.227,-0.133),Vector3(0.074,0.050,0.030),reflective)
	_add_wear([torso])
	_add_wear([helmet])
	for side in [-1.0,1.0]:
		_part(torso,Vector3(side*0.126,0.08,-0.14),Vector3(0.07,0.14,0.032),dark)
		_part(torso,Vector3(side*0.128,0.141,0.157),Vector3(0.039,0.296,0.045),reflective,true)
		_part(torso,Vector3(side*0.153,-0.092,0.164),Vector3(0.073,0.135,0.096),fabric,true)
		_part(torso,Vector3(side*0.135,-0.073,-0.147),Vector3(0.085,0.082,0.069),dark,true)
		for arm in [false,true]:
			var mount := Node3D.new()
			mount.position = Vector3(side*(0.31 if arm else 0.118),1.48 if arm else 1.035,0)
			_avatar.add_child(mount)
			_limbs.append(mount)
			var upper_length := 0.28 if arm else 0.44
			var lower_length := 0.27 if arm else 0.43
			var width := 0.145 if arm else 0.18
			var upper := _part(mount,Vector3.DOWN*(upper_length*0.5+0.015),Vector3(width,upper_length,0.18),fabric,true)
			var hinge := Node3D.new()
			hinge.position.y = -upper_length-0.035
			mount.add_child(hinge)
			_lower_limbs.append(hinge)
			var lower := _part(hinge,Vector3.DOWN*lower_length*0.5,Vector3(width*0.85,lower_length,0.16),fabric,true)
			_part(lower,Vector3(0,-lower_length*0.25,0),Vector3(0.14,0.04,0.155),reflective,true)
			if arm:
				_part(upper,Vector3(-side*0.032,0.086,0),Vector3(0.221,0.18,0.19),orange,true)
				_part(lower,Vector3(0,-0.16,-0.018),Vector3(0.147,0.13,0.16),dark,true)
			else:
				_part(lower,Vector3(0,0.155,-0.069),Vector3(0.149,0.15,0.079),dark,true)
				_part(lower,Vector3(0,-0.181,-0.052),Vector3(0.167,0.101,0.246),dark,true)
				_part(lower,Vector3(0,-0.211,-0.061),Vector3(0.157,0.034,0.227),dark)
			_add_wear([upper,lower])

func _add_wear(meshes: Array[MeshInstance3D]) -> void:
	var overlay := ShaderMaterial.new()
	overlay.shader = WEAR
	for mesh in meshes:
		mesh.material_overlay = overlay
	_region_wear.append(overlay)

func _part(parent: Node3D, center: Vector3, dimensions: Vector3, tint: Color, rounded := false) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh: PrimitiveMesh
	if rounded:
		var capsule := CapsuleMesh.new()
		capsule.radial_segments = 12
		capsule.rings = 5
		capsule.radius = 0.5
		capsule.height = 2.0
		# Size the generated geometry so the ragdoll collider uses the same dimensions.
		var geometry := ArrayMesh.new()
		var arrays := capsule.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var scale_factor := dimensions*Vector3(1.0,0.5,1.0)
		for index in vertices.size():
			vertices[index] *= scale_factor
			normals[index] = (normals[index]/scale_factor).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		part.mesh = geometry
	else:
		var box := BoxMesh.new()
		box.size = dimensions
		mesh = box
		part.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.46 if tint == Color("#314d5c") else 0.83
	part.material_override = material
	part.position = center
	parent.add_child(part)
	return part
