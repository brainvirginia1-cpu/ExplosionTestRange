extends RefCounted
## A fixed-step parcel model for the visible cloud. Positions use local effect units.
const COUNT := 120
const GAS_COUNT := 72
const DUST_LOAD := [1.05, 0.72, 0.22, 1.20, 1.65]
var release_phase := PackedFloat32Array()
var aspect := PackedFloat32Array()
const DT := 1.0 / 60.0
const STYLES := [
	# outward motion, upward motion, starting heat, spreading rate
	Vector4(1.00, 0.89, 0.90, 1.00), Vector4(0.72, 1.27, 1.10, 1.18),
	Vector4(1.18, 0.66, 0.80, 0.80), Vector4(1.56, 0.42, 0.93, 1.43),
	Vector4(0.76, 1.42, 0.32, 0.76)
]
var position := PackedVector3Array()
var velocity := PackedVector3Array()
var radius := PackedFloat32Array()
var heat := PackedFloat32Array()
var spin := PackedFloat32Array()
# Keep independent snapshots at the ends of the render interval.
var previous_position := PackedVector3Array()
var previous_radius := PackedFloat32Array()
var previous_heat := PackedFloat32Array()
var tick := 0
var style := 0
var variation := 0
var crown := 0.0

func initialize(type: int, event_seed: int, cap: float) -> void:
	style = type
	variation = event_seed
	crown = cap
	tick = 0
	var random := RandomNumberGenerator.new()
	random.seed = variation
	var settings: Vector4 = STYLES[style]
	position.resize(COUNT)
	velocity.resize(COUNT)
	radius.resize(COUNT)
	heat.resize(COUNT)
	spin.resize(COUNT)
	aspect.resize(COUNT)
	release_phase.resize(COUNT)
	# Adjacent parcels share an eddy so the outline breaks into billows of different heights.
	var orientation := random.randf_range(0,TAU)
	for i in COUNT:
		var eddy := i % 9
		var angle := orientation + TAU*eddy/9.0 + random.randf_range(-0.22,0.22)
		var radial := Vector3(cos(angle),0,sin(angle))
		var speed := (0.63+0.29*cos(eddy*2.17))*random.randf_range(0.70,1.18)
		var dust := i >= GAS_COUNT
		var altitude := 0.22 if type==2 else 0.075
		position[i] = radial*random.randf_range(0.0,0.05)+Vector3.UP*(0.04 if dust else altitude+random.randf_range(0,0.04))
		velocity[i] = radial*speed*settings.x + Vector3.UP*((0.68+0.36*sin(eddy*2.7))*random.randf_range(0.72,1.27)*settings.y if not dust else 0.12)
		radius[i] = random.randf_range(0.04,0.085)
		heat[i] = 0.0 if dust else settings.z*(0.92+0.20*cos(eddy*2.7))*random.randf_range(0.78,1.18)
		aspect[i] = 1.0
		if dust:
			var jet := (i-GAS_COUNT)%4 == 0
			var load_factor: float = DUST_LOAD[type]
			var ring := floori((i-GAS_COUNT)/16.0)
			var azimuth := orientation + TAU*(float(i%16)+ring*0.34)/16.0
			radial = Vector3(cos(azimuth),0,sin(azimuth))
			var spread := 0.96 + 0.13*cos(azimuth*3.0)
			var distance := 0.055+0.10*ring
			position[i] = radial*distance+Vector3.UP*0.04
			release_phase[i] = distance/2.25
			velocity[i] = radial*spread*(0.56 if jet else 1.48)*sqrt(load_factor)
			velocity[i].y = spread*(1.37 if jet else 0.38)*sqrt(load_factor)
			aspect[i] = random.randf_range(0.80,1.15) if jet else random.randf_range(0.40,0.66)
			radius[i] = 0.0
		if i<20 and crown>0.45:
			# Entrained material rises from the foot of the large plume.
			velocity[i] *= 0.20
			radius[i] *= 0.65
		spin[i] = random.randf_range(-1.0,1.0)

	previous_position = position.duplicate()
	previous_radius = radius.duplicate()
	previous_heat = heat.duplicate()

func advance(time: float, _legacy_wind: float, rain: bool) -> void:
	var goal := ceili(time / DT)
	if goal < tick:
		initialize(style,variation,crown)
	while tick < goal:
		if tick + 1 == goal:
			previous_position = position.duplicate()
			previous_radius = radius.duplicate()
			previous_heat = heat.duplicate()
		var center := Vector3.ZERO
		for i in GAS_COUNT:
			center += position[i]
		center /= float(GAS_COUNT)
		var now := tick*DT
		for i in COUNT:
			var dust := i >= GAS_COUNT
			if i<20 and crown>0.45 and now < float(i)*0.23:
				continue
			if dust and now < release_phase[i]:
				continue
			var off := position[i]-center
			var side := Vector3(off.x,0,off.z)
			var v := velocity[i]
			var drag := 1.46 if dust else 1.67
			var force := -v*drag
			if dust:
				var ground_dir := Vector3(position[i].x,0,position[i].z).normalized()
				var heavy := (i-GAS_COUNT)%4 == 0
				var wake := exp(-maxf(0,now-release_phase[i])*2.6)
				force += ground_dir*wake*(1.65 if not heavy else 0.62)
				force.y += 0.70*wake - (1.22 if heavy else 0.32)*(1.4 if rain else 1.0)
			else:
				var lift := (0.30+heat[i]*0.56)*exp(-now*0.19)
				force.y += lift
				# Hot parcels in the central updraft rise and roll outward at the top.
				var cap_flow := crown*smoothstep(0.24,0.96,now)
				force.y += cap_flow*(0.38*exp(-side.length_squared()*15.0)-side.length()*0.37)
				force += side.normalized()*cap_flow*clampf(off.y*1.6,-0.10,0.34)
				if style == 1:
					# Lift the hot core and turn the crest outwards into cooler descending edges.
					var roll := smoothstep(0.12,0.85,now)*exp(-now*0.65)
					force += side.normalized()*off.y*roll*1.8
					force.y += (0.19-side.length())*roll*1.4
				force += Vector3(-off.z,0,off.x)*(0.29+spin[i]*0.32)
			v += force*DT
			position[i] += v*DT
			if position[i].y < 0.04:
				position[i].y = 0.04
				v.y = maxf(0.0,v.y)
			velocity[i] = v
			radius[i] += DT*STYLES[style].w*(0.060+0.11*v.length())/(1.0+now*0.49)
			if dust:
				radius[i] += DT*0.15*exp(-now*0.94)*sqrt(float(DUST_LOAD[style]))
			heat[i] *= exp(-DT*(1.16 if rain else 0.91))
		tick += 1
