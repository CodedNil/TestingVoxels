extends Node3D


var extents = Vector3(70, 35, 70)
var voxelSize = 0.5

func _ready():
	var noiseHeight = FastNoiseLite.new()
	noiseHeight.set_noise_type(FastNoiseLite.TYPE_SIMPLEX)
	noiseHeight.set_frequency(0.03)
	noiseHeight.seed = 1234
	
	var noiseRoom = FastNoiseLite.new()
	noiseRoom.set_noise_type(FastNoiseLite.TYPE_SIMPLEX)
	noiseRoom.set_frequency(0.3)
	noiseRoom.seed = 123
	
	var noiseRoomHeight = FastNoiseLite.new()
	noiseRoomHeight.set_noise_type(FastNoiseLite.TYPE_SIMPLEX)
	noiseRoomHeight.set_frequency(0.1)
	noiseRoomHeight.seed = 12345

	var nVoxels = 0
	
	# Create boxes within extents
	for x in range(-extents.x / voxelSize / 2, extents.x / voxelSize / 2):
		for z in range(-extents.z / voxelSize / 2, extents.z / voxelSize / 2):
			var pos2d = Vector2(x * voxelSize, z * voxelSize)

			# Get angle from center with x and z, from -pi to pi
			var roomAngle = pos2d.angle_to_point(Vector2(0, 0))
			# Get 2d distance from center with x and z
			var roomDist = pos2d.length()

			# Calculate room size, based on noise from the angle
			var roomSize0 = 20 + noiseRoom.get_noise_1d(-PI) * 20
			var roomSize = 20 + noiseRoom.get_noise_1d(roomAngle) * 20
			# For the last 25% of the angle, so from half pi to pi, lerp towards roomSize0
			var roomSizeLerp = lerp(roomSize, roomSize0, (roomAngle - PI / 2) / (PI / 2)) if roomAngle > PI / 2 else roomSize

			# Calculate if we are inside the room, if we are at the wall, and distance from wall
			var roomInside = roomDist < roomSizeLerp
			if roomInside:
				for y in range(-extents.y / voxelSize / 2, extents.y / voxelSize / 2):
					var pos = Vector3(x * voxelSize, y * voxelSize, z * voxelSize)
					# Get 3d distance from center
					var roomHeight = 4 if y < 0 else 2 + noiseRoomHeight.get_noise_2dv(pos2d) * 1
					var roomDist3d = Vector3(x * voxelSize, y * voxelSize * roomHeight, z * voxelSize).length()
					if abs(roomDist3d - roomSizeLerp) < voxelSize * 7:

						# Add height to y based on noise
						pos.y += noiseHeight.get_noise_2dv(pos2d) * 2
						# Add jiggle to x and z based on noise
						pos.x += noiseHeight.get_noise_2dv(Vector2(z * voxelSize, y * voxelSize) ) * 0.5
						pos.z += noiseHeight.get_noise_2dv(Vector2(x * voxelSize, y * voxelSize) ) * 0.5

						# Create a new BoxMesh
						var box = BoxMesh.new()
						box.size = Vector3(voxelSize, voxelSize, voxelSize)
						# Assign a random color to the box
						var shade = abs(y * voxelSize) / 5
						var color = Color(shade, shade, shade)
						# Create a new MeshInstance
						var mesh = MeshInstance3D.new()
						mesh.mesh = box
						mesh.material_override = StandardMaterial3D.new()
						mesh.material_override.albedo_color = color
						# Add mesh as a child of this node
						add_child(mesh)
						# Position the mesh
						mesh.transform.origin = pos

						# Add collision shape
						# var shape = CollisionShape3D.new()
						# shape.shape = box
						# mesh.add_child(shape)

						# Increase voxel count
						nVoxels += 1
	
	print("Created ", nVoxels, " voxels")
