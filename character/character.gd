extends CharacterBody3D

# Mouse state
var mouse_position: Vector2 = Vector2(0.0, 0.0)
var total_pitch: float = 0.0

@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Keyboard state
var _w = false
var _s = false
var _a = false
var _d = false
var _shift = false
var _space = false

func _input(event):
	# Receives mouse motion
	if event is InputEventMouseMotion:
		mouse_position = event.relative
	
	# Receives mouse button input
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT: # Only allows rotation if right click down
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE)

	# Receives key input
	if event is InputEventKey:
		match event.keycode:
			KEY_W:
				_w = event.pressed
			KEY_S:
				_s = event.pressed
			KEY_A:
				_a = event.pressed
			KEY_D:
				_d = event.pressed
			KEY_SHIFT:
				_shift = event.pressed
			KEY_SPACE:
				_space = event.pressed

# Updates mouselook and movement every frame
func _process(_delta):
	# Only rotates mouse if the mouse is captured
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		mouse_position *= 0.25
		var yaw = mouse_position.x
		var pitch = mouse_position.y
		mouse_position = Vector2(0, 0)
		
		# Prevents looking up/down too far
		pitch = clamp(pitch, -90 - total_pitch, 90 - total_pitch)
		total_pitch += pitch
	
		rotate_y(deg_to_rad(-yaw))
		get_node("CameraRotator").rotate_object_local(Vector3(1,0,0), deg_to_rad(-pitch))

# Updates camera movement
func _physics_process(delta):
	# Computes desired direction from key states
	var direction: Vector3 = ((_d as float) - (_a as float)) * get_transform().basis.x.normalized() + ((_s as float) - (_w as float)) * get_transform().basis.z.normalized()
	
	# Compute modifiers' speed multiplier
	var speed_multi = 2 if _shift else 1

	# Add direction to movement
	velocity += direction * speed_multi
	# Jump
	if _space and is_on_floor():
		velocity.y = 8
	# Drag on xz plane
	velocity.x *= 0.9
	velocity.z *= 0.9
	# Apply gravity
	velocity.y -= gravity * delta
	# Move
	move_and_slide()