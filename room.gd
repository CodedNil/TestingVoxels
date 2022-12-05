extends Node3D


var extents = Vector3(25, 5, 25)
var voxelSize = 0.25

func _ready():
	var noiseHeight = FastNoiseLite.new()
	noiseHeight.set_noise_type(FastNoiseLite.TYPE_SIMPLEX)
	noiseHeight.set_frequency(0.03)
	noiseHeight.seed = 1234
	
	var noiseRoom = FastNoiseLite.new()
	noiseRoom.set_noise_type(FastNoiseLite.TYPE_SIMPLEX)
	noiseRoom.set_frequency(0.3)
	noiseRoom.seed = 123
	
	# Create boxes within extents
	for x in range(-extents.x / voxelSize / 2, extents.x / voxelSize / 2):
		for z in range(-extents.z / voxelSize / 2, extents.z / voxelSize / 2):
			var pos2d = Vector2(x * voxelSize, z * voxelSize)

			# Get angle from center with x and z, from -pi to pi
			var roomAngle = pos2d.angle_to_point(Vector2(0, 0))
			# Get 2d distance from center with x and z
			var roomDist = pos2d.length()

			# Calculate room size, based on noise from the angle
			var roomSize0 = 6 + noiseRoom.get_noise_1d(-PI) * 5
			var roomSize = 6 + noiseRoom.get_noise_1d(roomAngle) * 5
			# For the last 25% of the angle, so from half pi to pi, lerp towards roomSize0
			var roomSizeLerp = lerp(roomSize, roomSize0, (roomAngle - PI / 2) / (PI / 2)) if roomAngle > PI / 2 else roomSize

			# Calculate if we are inside the room, if we are at the wall, and distance from wall
			var roomInside = roomDist < roomSizeLerp
			var roomWall = abs(roomDist - roomSizeLerp) < voxelSize
			var roomDistWall = abs(roomDist - roomSizeLerp)
			if roomInside or roomWall:
				for y in range(-extents.y / voxelSize / 2, extents.y / voxelSize / 2):
					if roomWall or y == 0:
						var pos = Vector3(x * voxelSize, y * voxelSize, z * voxelSize)

						# Set y to simplex noise
						pos.y += noiseHeight.get_noise_2dv(pos2d) * 2
						if roomDistWall < 2:
							pos.y += (2 - roomDistWall) / 2

						# Create a new BoxMesh
						var box = BoxMesh.new()
						box.size = Vector3(voxelSize, voxelSize, voxelSize)
						# Assign a random color to the box
						var color = Color((roomAngle + PI) / (PI * 2), 0, 0)#Color(randf(), randf(), randf())
						# Create a new MeshInstance
						var mesh = MeshInstance3D.new()
						mesh.mesh = box
						mesh.material_override = StandardMaterial3D.new()
						mesh.material_override.albedo_color = color
						# Add mesh as a child of this node
						add_child(mesh)
						# Position the mesh
						mesh.transform.origin = pos
