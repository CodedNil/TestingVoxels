extends CharacterBody3D

# Modifier keys' speed multiplier
const SHIFT_MULTIPLIER = 2.5

@export_range(0.0, 1.0) var sensitivity: float = 0.25

# Mouse state
var _mouse_position: Vector2 = Vector2(0.0, 0.0)
var _total_pitch: float = 0.0

# Movement state
var _direction: Vector3 = Vector3(0.0, 0.0, 0.0)
var _velocity: Vector3 = Vector3(0.0, 0.0, 0.0)
var _acceleration: float = 30
var _deceleration: float = -10
var _vel_multiplier: float = 4

@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * 10

# Keyboard state
var _w = false
var _s = false
var _a = false
var _d = false
var _q = false
var _e = false
var _shift = false
var _space = false

func _input(event):
	# Receives mouse motion
	if event is InputEventMouseMotion:
		_mouse_position = event.relative
	
	# Receives mouse button input
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT: # Only allows rotation if right click down
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE)
			MOUSE_BUTTON_WHEEL_UP: # Increases max velocity
				_vel_multiplier = clamp(_vel_multiplier * 1.1, 0.2, 20)
			MOUSE_BUTTON_WHEEL_DOWN: # Decereases max velocity
				_vel_multiplier = clamp(_vel_multiplier / 1.1, 0.2, 20)

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
			KEY_Q:
				_q = event.pressed
			KEY_E:
				_e = event.pressed
			KEY_SHIFT:
				_shift = event.pressed
			KEY_SPACE:
				_space = event.pressed

# Updates mouselook and movement every frame
func _process(_delta):
	# Only rotates mouse if the mouse is captured
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_mouse_position *= sensitivity
		var yaw = _mouse_position.x
		var pitch = _mouse_position.y
		_mouse_position = Vector2(0, 0)
		
		# Prevents looking up/down too far
		pitch = clamp(pitch, -90 - _total_pitch, 90 - _total_pitch)
		_total_pitch += pitch
	
		rotate_y(deg_to_rad(-yaw))
		get_node("CameraRotator").rotate_object_local(Vector3(1,0,0), deg_to_rad(-pitch))

# Updates camera movement
func _physics_process(delta):
	# Computes desired direction from key states
	_direction = ((_d as float) - (_a as float)) * get_transform().basis.x.normalized() + ((_e as float) - (_q as float)) * get_transform().basis.y.normalized() + ((_s as float) - (_w as float)) * get_transform().basis.z.normalized()
	
	# Computes the change in velocity due to desired direction and "drag"
	# The "drag" is a constant acceleration on the camera to bring it's velocity to 0
	var offset = _direction.normalized() * _acceleration * _vel_multiplier * delta \
		+ _velocity.normalized() * _deceleration * _vel_multiplier * delta
	
	# Compute modifiers' speed multiplier
	var speed_multi = 1
	if _shift: speed_multi *= SHIFT_MULTIPLIER
	
	# Checks if we should bother translating the camera
	if _direction == Vector3.ZERO and offset.length_squared() > _velocity.length_squared():
		# Sets the velocity to 0 to prevent jittering due to imperfect deceleration
		_velocity = Vector3.ZERO
	else:
		# Clamps speed to stay within maximum value (_vel_multiplier)
		_velocity.x = clamp(_velocity.x + offset.x, -_vel_multiplier, _vel_multiplier)
		_velocity.y = clamp(_velocity.y + offset.y, -_vel_multiplier, _vel_multiplier)
		_velocity.z = clamp(_velocity.z + offset.z, -_vel_multiplier, _vel_multiplier)


		velocity = _velocity * speed_multi
		velocity.y -= gravity * delta
		move_and_slide()