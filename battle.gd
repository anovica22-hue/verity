# Original prototype by CodeRabbit Agent. Rigid-part IK, no external dependencies.
extends Node3D
var player: Node3D
var model: Node3D
var camera: Camera3D
var sword: Node3D
var grip: Node3D
var back: Node3D
var torso: Node3D
var arms: Array = []
var legs: Array = []
var enemies: Array = []
var hud: Label
var yaw := 0.0
var pitch := 0.15
var camera_distance := 4.2
var drawn := false
var action := "idle"
var phase := 0.0
var time := 0.0
var drag_blend := 0.0
var hit_done := false
var combo := 0
var queued := false
var health := 100
var kills := 0
var start_transform: Transform3D
var grip_error := 0.0
var max_grip_error := 0.0
var test_mode := false
var test_step := 0
var test_timer := 0.0
var test_hits := false
var captured := false
var hit_pause := 0.0
var edge_roll := 0.0
var struck: Array = []
var previous_blade_base := Vector3.ZERO
var previous_blade_tip := Vector3.ZERO
var blade_mesh: MeshInstance3D
var previous_cut_point := Vector3.ZERO
var cut_sample_ready := false
var blade_contact_points: Array[Vector3] = []

func find_part(root: Node, key: String) -> Node3D:
	if root is Node3D and str(root.name).begins_with(key):
		return root
	for child in root.get_children():
		var result := find_part(child, key)
		if result != null:
			return result
	return null

func collect_fingers(root: Node, found: Array) -> void:
	if root is Node3D and str(root.name).begins_with("Finger"):
		found.append(root)
	for child in root.get_children():
		collect_fingers(child,found)

func block(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	m.material_override = mat
	add_child(m)
	m.position = pos
	return m

func _ready() -> void:
	test_mode = "--smoke-test" in OS.get_cmdline_user_args()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("171923")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b5bdd0")
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-25,0)
	light.light_energy = 1.4
	light.shadow_enabled = true
	add_child(light)
	block(Vector3(80,0.2,100),Vector3(0,-0.1,-25),Color("383a32"))
	block(Vector3(22,7,2),Vector3(0,3.5,-48),Color("3d3945"))
	block(Vector3(3.4,5,0.1),Vector3(0,2.5,-46.94),Color("11131a"))
	block(Vector3(8,15,7),Vector3(0,7.5,-53),Color("48414d"))
	for x in [-11.0,11.0]:
		block(Vector3(4,12,4),Vector3(x,6,-48),Color("46424e"))
		var roof := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0
		cone.bottom_radius = 3
		cone.height = 5
		roof.mesh = cone
		add_child(roof)
		roof.position = Vector3(x,14.5,-48)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("242838")
		roof.material_override = mat
	for i in range(18):
		block(Vector3(0.7,1,2),Vector3(-10.2+i*1.2,7.5,-48),Color("55505b"))
	for i in range(24):
		block(Vector3(0.4,0.25,0.5),Vector3(sin(i*2.4)*12,0.1,-8+cos(i*2.4)*10),Color("514b49"))
	player = Node3D.new()
	add_child(player)
	model = load("res://assets/guts-black-swordsman.glb").instantiate()
	player.add_child(model)
	player.rotation.y = PI
	torso = find_part(model,"Spine_Chest")
	sword = find_part(model,"Dragonslayer_Weapon")
	blade_mesh = find_part(sword,"Massive_Blade")
	# Cache the actual blade silhouette, including the point and bevels.
	for surface in range(blade_mesh.mesh.get_surface_count()):
		var vertices: PackedVector3Array = blade_mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			blade_contact_points.append(sword.to_local(blade_mesh.to_global(vertex)))
	back = Node3D.new()
	player.add_child(back)
	back.position = Vector3(0.2,1.45,-0.4)
	back.rotation.z = -0.5
	grip = Node3D.new()
	player.add_child(grip)
	sword.reparent(back)
	sword.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*0.6883125912),Vector3.ZERO)
	for prefix in ["Right_Shoulder","Prosthetic_Left_Shoulder"]:
		var shoulder := find_part(model,prefix)
		var elbow := find_part(shoulder,"Elbow")
		var wrist := find_part(shoulder,"Wrist_Hand")
		var fingers: Array = []
		collect_fingers(wrist,fingers)
		arms.append({"fingers":fingers,"shoulder":shoulder,"elbow":elbow,"wrist":wrist,"upper":elbow.position,"lower":wrist.position})
	for prefix in ["Left_Hip","Right_Hip"]:
		var hip := find_part(model,prefix)
		legs.append({"hip":hip,"knee":find_part(hip,"Knee"),"ankle":find_part(hip,"Ankle")})
	var names := ["knight-iron-guard","knight-crimson-pikeman","knight-black-executioner"]
	for i in range(3):
		var e := Node3D.new()
		add_child(e)
		e.add_child(load("res://assets/"+names[i]+".glb").instantiate())
		e.position = Vector3((i-1)*1.5,0,-3.7)
		enemies.append({"node":e,"hp":3,"cooldown":2.0,"flash":0.0})
	camera = Camera3D.new()
	camera.fov = 58
	add_child(camera)
	camera.position = Vector3(0,2.6,5)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	canvas.add_child(hud)
	hud.position = Vector2(20,16)
	hud.add_theme_color_override("font_color",Color("eee1cd"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(2.8,camera_distance-.35)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(7,camera_distance+.35)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x*0.005
		pitch = clampf(pitch+event.relative.y*0.003,0.05,0.6)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			draw_sword()
		if event.keycode == KEY_SPACE:
			attack()
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()

func draw_sword() -> void:
	if action != "idle" or drawn:
		return
	action = "draw"
	phase = 0
	for arm in arms:
		arm["draw_start"] = arm.wrist.global_position
	start_transform = sword.global_transform
	sword.reparent(self)

func attack() -> void:
	if health <= 0:
		return
	if not drawn:
		draw_sword()
	elif action == "attack":
		if phase > 0.25:
			queued = true
	elif action == "idle":
		action = "recover"
		phase = 0

func solve_arm(chain: Dictionary, target: Vector3, side: float) -> float:
	var shoulder: Node3D = chain.shoulder
	var elbow: Node3D = chain.elbow
	var wrist: Node3D = chain.wrist
	var parent: Node3D = shoulder.get_parent()
	var s := shoulder.position
	var t := parent.to_local(target)
	var axis := (t-s).normalized()
	var a: float = chain.upper.length()
	var b: float = chain.lower.length()
	var distance := clampf(t.distance_to(s),0.001,a+b-0.0001)
	var pole := Vector3(side,-0.5,-0.15)
	pole = (pole-axis*pole.dot(axis)).normalized()
	var along := (a*a-b*b+distance*distance)/(2*distance)
	var e := s+axis*along+pole*sqrt(maxf(0,a*a-along*along))
	shoulder.quaternion = Quaternion(chain.upper.normalized(),(e-s).normalized())
	elbow.quaternion = Quaternion(chain.lower.normalized(),(shoulder.to_local(target)-elbow.position).normalized())
	wrist.quaternion = elbow.global_basis.get_rotation_quaternion().inverse()*sword.global_basis.orthonormalized().get_rotation_quaternion()
	return wrist.global_position.distance_to(target)

func plant_leg(leg: Dictionary, target: Vector3) -> void:
	var hip: Node3D = leg.hip
	var knee: Node3D = leg.knee
	var ankle: Node3D = leg.ankle
	var parent: Node3D = hip.get_parent()
	var s := hip.position
	var t := parent.to_local(target)
	var upper := knee.position
	var lower := ankle.position
	var a := upper.length()
	var b := lower.length()
	var axis := (t-s).normalized()
	var distance := clampf(t.distance_to(s),.001,a+b-.0001)
	var pole := Vector3(0,0,1)
	pole = (pole-axis*pole.dot(axis)).normalized()
	var along := (a*a-b*b+distance*distance)/(2*distance)
	var joint := s+axis*along+pole*sqrt(maxf(0,a*a-along*along))
	hip.quaternion = Quaternion(upper.normalized(),(joint-s).normalized())
	knee.quaternion = Quaternion(lower.normalized(),(hip.to_local(target)-knee.position).normalized())
	ankle.global_basis = player.global_basis*leg.foot_basis

func _physics_process(dt: float) -> void:
	if player == null:
		return
	if hit_pause > 0:
		hit_pause = maxf(0,hit_pause-dt)
		dt *= .12
	time += dt
	phase += dt
	var move := Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	if test_mode:
		move = smoke_step(dt)
	var moving := move.length() > 0.1 and health > 0
	if moving and action != "draw":
		move = move.normalized().rotated(Vector3.UP,yaw)
		player.position += move*dt*2.2*(0.3 if action == "attack" else 1.0)
		player.position.x = clampf(player.position.x,-25,25)
		player.position.z = clampf(player.position.z,-40,20)
		player.rotation.y = lerp_angle(player.rotation.y,atan2(move.x,move.z),minf(1,dt*12))
	drag_blend = move_toward(drag_blend,1.0 if moving and drawn and action == "idle" else 0.0,dt*3)
	if action == "recover" and drag_blend < 0.01:
		action = "attack"
		phase = 0
		hit_done = false
		struck.clear()
		for leg in legs:
			leg["plant"] = player.to_local(leg.ankle.global_position)
			leg["world_plant"] = leg.ankle.global_position
			leg["foot_basis"] = player.global_basis.inverse()*leg.ankle.global_basis
	# Authored full-body poses: gather weight, overhead load, diagonal cut,
	# low follow-through and deliberate return to guard. Seconds are nonuniform.
	var direction := 1.0 if combo%2 == 0 else -1.0
	var attack_weight := 0.0
	var body_turn := 0.0
	var body_lean := 0.0
	grip.position = Vector3(0.08,1.28,0.36)
	grip.quaternion = Quaternion(Vector3.DOWN,Vector3(.65,.65,.39).normalized())
	if action == "attack":
		var keys := [0.0,0.20,0.43,0.56,0.74,1.02,1.36]
		var positions := [Vector3(.08,1.28,.36),Vector3(.12,1.55,.30),Vector3(.15,1.86,.30),Vector3(.02,1.48,.32),Vector3(-.20,1.05,.26),Vector3(-.12,1.18,.30),Vector3(.08,1.28,.36)]
		var turns := [0.0,.22,.56,-.18,-.60,-.28,0.0]
		var leans := [0.0,-.03,-.08,.10,.16,.08,0.0]
		if combo%3 == 2:
			# Third strike is a committed overhead chop, not another mirror.
			positions[1] = Vector3(0,1.58,.30)
			positions[2] = Vector3(0,1.91,.30)
			positions[3] = Vector3(0,1.48,.34)
			positions[4] = Vector3(.04,1.05,.32)
			turns = [0.0,.08,.12,0.0,-.12,-.08,0.0]
			leans = [0.0,-.06,-.14,.10,.22,.10,0.0]
		positions[0].x *= direction
		positions[6].x *= direction
		var k := 0
		while k < keys.size()-2 and phase > keys[k+1]:
			k += 1
		var t := smoothstep(keys[k],keys[k+1],phase)
		# Preserve cutting velocity across the intermediate contact pose.
		if k == 2 or k == 3:
			t = clampf((phase-keys[k])/(keys[k+1]-keys[k]),0,1)
		grip.position = positions[k].lerp(positions[k+1],t)
		grip.position.x *= direction
		var tip_directions := [Vector3(-.43,.86,.26),Vector3(.28,.92,-.22),Vector3(.38,.82,-.42),Vector3(-.18,.08,.98),Vector3(-.62,-.65,.44),Vector3(-.56,-.22,.80),Vector3(-.43,.86,.26)]
		tip_directions[0] = Vector3(.65,.65,.39).normalized()
		tip_directions[6] = tip_directions[0]
		tip_directions[0].x *= direction
		tip_directions[6].x *= direction
		if combo%3 == 2:
			tip_directions[2] = Vector3(0,.90,-.44)
			tip_directions[3] = Vector3(0,.05,1)
			tip_directions[4] = Vector3(0,-.72,.69)
		var tip_direction: Vector3 = tip_directions[k].normalized().slerp(tip_directions[k+1].normalized(),t)
		tip_direction.x *= direction
		grip.quaternion = Quaternion(Vector3.DOWN,tip_direction)
		body_turn = lerpf(turns[k],turns[k+1],t)*direction
		body_lean = lerpf(leans[k],leans[k+1],t)
		attack_weight = sin(clampf(phase/1.36,0,1)*PI)
	torso.rotation = Vector3(body_lean,body_turn, -body_turn*.12)
	model.rotation.y = body_turn*.45
	model.rotation.x = body_lean*.35
	model.position.y = -attack_weight*.095
	model.position.z = attack_weight*.22
	if action == "attack":
		# Drive the cutting grip from the moving shoulder line, so torso
		# rotation does not pull an apparently extended sword into the chest.
		var extension := smoothstep(.40,.54,phase)*(1.0-smoothstep(.76,.96,phase))
		var shoulders: Vector3 = (arms[0].shoulder.global_position+arms[1].shoulder.global_position)*.5
		var extended := shoulders+torso.global_basis.z.normalized()*.54-Vector3.UP*.04
		grip.position = grip.position.lerp(player.to_local(extended),extension)
	var drag_origin := Vector3.ZERO
	var drag_rotation := Quaternion.IDENTITY
	if drag_blend > 0:
		# A loaded, nearly straight right arm hangs from the shoulder.
		# Solve the blade slope from this hand height and its true tip length.
		var shoulder := player.to_local(arms[0].shoulder.global_position)
		var hand := shoulder+Vector3(.055,-.575,-.09+sin(time*9)*.012)
		var tip_length := -blade_contact_points[0].y
		for point in blade_contact_points:
			tip_length = maxf(tip_length,-point.y)
		var drop := clampf((hand.y-.012)/((tip_length-.09)*.6883125912),.1,.95)
		var trailing := Vector3(.18,0,-1).normalized()*sqrt(1-drop*drop)
		var q := Quaternion(Vector3.DOWN,Vector3(trailing.x,-drop,trailing.z))
		drag_origin = hand-q*Vector3(0,-.09*.6883125912,0)
		drag_rotation = q
		grip.position = grip.position.lerp(drag_origin,drag_blend)
		grip.quaternion = grip.quaternion.slerp(q,drag_blend)
	# Blade geometry: Y is length, X spans the two cutting edges, Z is
	# the broad-face normal. Roll the whole grip, including both wrists.
	var cut_point := grip.position-grip.basis.y*1.15
	var cut_velocity := cut_point-previous_cut_point
	previous_cut_point = cut_point
	var desired_edge := Vector3(0,0,1)
	if cut_sample_ready and action == "attack" and phase > .43 and phase < .74 and cut_velocity.length_squared() > .00000001:
		desired_edge = cut_velocity.normalized()
	cut_sample_ready = true
	var local_edge := grip.basis.inverse()*desired_edge
	if Vector2(local_edge.x,local_edge.z).length() > .001:
		var target_roll := atan2(-local_edge.z,local_edge.x)
		# Both sides are sharpened; choose the equivalent edge without a flip.
		while target_roll-edge_roll > PI/2:
			target_roll -= PI
		while target_roll-edge_roll < -PI/2:
			target_roll += PI
		edge_roll = move_toward(edge_roll,target_roll,dt*14)
	grip.rotate_object_local(Vector3.UP,edge_roll)
	if drag_blend > 0:
		# Correct the completed drag pose, then blend that small correction.
		# Constraining the intermediate guard would pull the hands off the hilt.
		var lowest := INF
		var rolled_drag := Basis(drag_rotation)*Basis(Vector3.UP,edge_roll)
		for point in blade_contact_points:
			lowest = minf(lowest,(drag_origin+rolled_drag*(point*.6883125912)).y)
		grip.position.y += (.012-lowest)*drag_blend
	var gait := sin(time*9)*0.45 if moving else 0.0
	for i in range(2):
		var leg: Dictionary = legs[i]
		var side := -1.0 if i == 0 else 1.0
		leg.hip.rotation = Vector3(-0.15+gait*side+attack_weight*side*direction*.16,0,side*(0.16+attack_weight*.08)*(1-drag_blend))
		leg.knee.rotation.x = 0.3+maxf(0,-gait*side)*0.3+attack_weight*(.20+side*body_turn*.3)
		leg.ankle.rotation.x = -leg.hip.rotation.x-leg.knee.rotation.x
		leg.ankle.rotation.z = -leg.hip.rotation.z
		if action == "attack" and leg.has("plant"):
			var target: Vector3 = leg.world_plant
			var step := smoothstep(.12,.43,phase)
			if side*direction > 0:
				target += player.basis.z*step*.34
				target.y += sin(step*PI)*.10
			var recovery := smoothstep(.90,1.36,phase)
			target = target.lerp(player.to_global(leg.plant),recovery)
			plant_leg(leg,target)
	if action == "draw":
		var end := grip.global_transform.scaled_local(Vector3.ONE*0.6883125912)
		sword.global_transform = start_transform.interpolate_with(end,smoothstep(0,1,phase))
		if phase >= 1:
			sword.reparent(grip)
			sword.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*0.6883125912),Vector3.ZERO)
			drawn = true
			action = "idle"
	# Keep both authored grip targets inside each arm's reach before IK.
	# Move the common weapon control, never detach or stretch a hand.
	if drawn and action == "attack":
		var extension := smoothstep(.40,.54,phase)*(1.0-smoothstep(.76,.96,phase))
		var centers: Array[Vector3] = []
		var radii: Array[float] = []
		for i in range(2):
			var shoulder: Node3D = arms[i].shoulder
			var offset := sword.to_global(Vector3(0,-.09 if i == 0 else .10,0))-grip.global_position
			centers.append(shoulder.global_position-offset)
			radii.append((arms[i].upper.length()+arms[i].lower.length())*shoulder.get_parent().global_basis.get_scale().x*.97)
		var line := centers[1]-centers[0]
		var distance := line.length()
		var axis := line.normalized()
		var along := (radii[0]*radii[0]-radii[1]*radii[1]+distance*distance)/(2*distance)
		var circle := centers[0]+axis*along
		var outward := grip.global_position-circle
		outward = (outward-axis*outward.dot(axis)).normalized()
		var radius := sqrt(maxf(0,radii[0]*radii[0]-along*along))
		grip.global_position = grip.global_position.lerp(circle+outward*radius,extension)
	if drawn and drag_blend < .01:
		for iteration in range(6):
			for i in range(2):
				var target := sword.to_global(Vector3(0,-0.09 if i == 0 else 0.10,0))
				var shoulder: Node3D = arms[i].shoulder
				var reach: float = (arms[i].upper.length()+arms[i].lower.length())*shoulder.get_parent().global_basis.get_scale().x*.985
				var offset := target-shoulder.global_position
				if offset.length() > reach:
					grip.global_position -= offset.normalized()*(offset.length()-reach)
	grip_error = 0
	if drawn or action == "draw":
		for i in range(2):
			var target := sword.to_global(Vector3(0,-0.09 if i == 0 else 0.10,0))
			if action == "draw":
				target = arms[i].draw_start.lerp(target,smoothstep(0.05 if i == 0 else 0.4,0.85 if i == 0 else 1.0,phase))
			if i == 1 and drag_blend > 0:
				var shoulder: Vector3 = arms[i].shoulder.global_position
				var relaxed := shoulder+player.global_basis*Vector3(-.035,-.575,sin(time*9)*.13)
				target = target.lerp(relaxed,drag_blend)
			for finger in arms[i].fingers:
				finger.rotation.x = -1.1*(1.0 if i == 0 else 1.0-drag_blend)*smoothstep(0.4,1.0,phase) if action == "draw" else -1.1*(1.0 if i == 0 else 1.0-drag_blend)
			grip_error = maxf(grip_error,solve_arm(arms[i],target,1 if i == 0 else -1))
			if i == 1 and drag_blend > 0:
				# A free palm follows the hanging forearm rather than the sword.
				var wrist: Node3D = arms[i].wrist
				var relaxed := player.global_basis.get_rotation_quaternion()
				wrist.quaternion = wrist.get_parent().global_basis.get_rotation_quaternion().inverse()*wrist.global_basis.get_rotation_quaternion().slerp(relaxed,drag_blend)
	if drawn:
		max_grip_error = maxf(max_grip_error,grip_error)
	var bounds := blade_mesh.get_aabb()
	var blade_base := blade_mesh.to_global(Vector3(0,bounds.end.y,0))
	var blade_tip := blade_mesh.to_global(Vector3(0,bounds.position.y,0))
	if action == "attack":
		# Swept blade against each opponent's torso capsule, once per swing.
		if phase > .43 and phase < .78:
			for e in enemies:
				if e.hp <= 0 or e.node in struck:
					continue
				var contact := false
				for sample in range(5):
					var t := float(sample)/4
					var closest := Geometry3D.get_closest_points_between_segments(previous_blade_base.lerp(blade_base,t),previous_blade_tip.lerp(blade_tip,t),e.node.position+Vector3(0,.55,0),e.node.position+Vector3(0,1.5,0))
					if closest[0].distance_to(closest[1]) < .38:
						contact = true
				if contact:
					struck.append(e.node)
					e.hp -= 1
					e.flash = .55
					e.cooldown = maxf(e.cooldown,1.8)
					hit_pause = .055
					e.node.position += (e.node.position-player.position).normalized()*.12
					test_hits = true
					if e.hp == 0:
						kills += 1
		if phase >= 1.36:
			action = "idle"
			combo += 1
			if queued:
				queued = false
				attack()
	previous_blade_base = blade_base
	previous_blade_tip = blade_tip
	for e in enemies:
		if e.hp <= 0:
			e.node.rotation.z = lerp_angle(e.node.rotation.z,-PI/2,dt*5)
			continue
		var delta: Vector3 = player.position-e.node.position
		if delta.length() < 9 and delta.length() > 1.15 and health > 0:
			e.node.position += delta.normalized()*dt*0.45
			e.node.rotation.y = atan2(delta.x,delta.z)
		if delta.length() < 1.8 and e.flash <= 0:
			e.cooldown -= dt
		if delta.length() < 1.8 and e.cooldown < 0 and e.flash <= 0 and health > 0:
			health = maxi(0,health-8)
			e.cooldown = 2.0
		e.flash = maxf(0,e.flash-dt)
		e.node.rotation.x = sin(e.flash/0.55*PI)*-0.32
	var desired := player.position+Vector3(sin(yaw)*camera_distance,2.2+pitch*3,cos(yaw)*camera_distance)
	camera.position = camera.position.lerp(desired,minf(1,dt*8))
	camera.look_at(player.position+Vector3(0,1.45,0))
	hud.text = "BEFORE THE CITADEL | GODOT 4.6.1\nWASD move | E draw | SPACE attack/combo | RMB orbit | Wheel zoom | R restart\nHP %d | Defeated %d/3 | %s" % [health,kills,action]

func smoke_step(dt: float) -> Vector3:
	test_timer += dt
	if test_timer > 4.4 and not captured and "--capture" in OS.get_cmdline_user_args():
		captured = true
		capture_frame.call_deferred()
	if test_timer > 0.2 and test_step == 0:
		draw_sword()
		test_step = 1
	if test_timer > 2 and test_timer < 2.8:
		return Vector3(0,0,-1)
	if test_timer > 3 and action == "idle":
		for e in enemies:
			if e.hp > 0:
				var delta: Vector3 = e.node.position-player.position
				player.rotation.y = atan2(delta.x,delta.z)
				break
		attack()
	if test_timer > 16:
		print("SMOKE_RESULT kills=",kills," hits=",test_hits," drawn=",drawn," moved=",player.position," grip_error=",grip_error," max_grip_error=",max_grip_error)
		get_tree().quit(0 if test_hits and drawn and player.position.z < -0.2 and kills == 3 and max_grip_error < .005 else 1)
	return Vector3.ZERO

func capture_frame() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/godot-berserk-preview.png")
