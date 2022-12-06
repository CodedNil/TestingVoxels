extends Node3D

const extents = Vector3(70, 35, 70)
const voxelSize = 1


# Create noise generator class that can be initialised then have functions within
class DataGenerator:
	# A function to get a noise value with given frequency and seed, caches the fastnoiselite
	var noises = {}

	func getNoise(frequency, seed):
		var key = str(frequency) + ";" + str(seed)
		if key in noises:
			return noises[key]
		else:
			var noise = FastNoiseLite.new()
			noise.frequency = frequency
			noise.seed = seed
			noises[key] = noise
			return noise

	# Get data for a 2d point in the world
	func get_data_2d(pos2d):
		# World height offset for nice gradient slopes, -2 to 2, could have caves going uphill or downhill
		var noiseHeight = getNoise(0.03, 1234)
		var height = noiseHeight.get_noise_2dv(pos2d) * 2

		# Temperature scale, between 0 cold and 1 hot
		var temperature = 0.5 + getNoise(0.03, 1234).get_noise_2dv(pos2d) * 0.5

		# Get data for the room
		# Get angle from center with x and z, from -pi to pi
		var roomAngle = pos2d.angle_to_point(Vector2(0, 0))
		# Get 2d distance from center with x and z
		var roomDist = pos2d.length()

		# Calculate room size, based on noise from the angle
		var roomSize0 = 20 + getNoise(0.3, 123).get_noise_1d(-PI) * 20
		var roomSize = 20 + getNoise(0.3, 123).get_noise_1d(roomAngle) * 20
		# For the last 25% of the angle, so from half pi to pi, lerp towards roomSize0
		var roomSizeLerp = (
			lerp(roomSize, roomSize0, (roomAngle - PI / 2) / (PI / 2))
			if roomAngle > PI / 2
			else roomSize
		)

		# Calculate if we are inside the room, if we are at the wall, and distance from wall
		var roomInside2d = roomDist < roomSizeLerp

		return {
			"noiseHeight": noiseHeight,
			"height": height,
			"temperature": temperature,
			"roomInside2d": roomInside2d,
			"roomDist": roomDist,
			"roomSize": roomSizeLerp,
		}

	func get_data_3d(data2d, pos2d, pos3d):
		var roomHeight = 4 if pos3d.y < 0 else 2 + getNoise(0.1, 12345).get_noise_2dv(pos2d) * 1
		var roomDist3d = Vector3(pos3d.x * voxelSize, pos3d.y * voxelSize * roomHeight, pos3d.z * voxelSize).length()
		var roomInside3d = roomDist3d < data2d.roomSize

		# Jitter the pos3d
		var posJittered = Vector3(pos3d.x, pos3d.y, pos3d.z)
		# Add height to y based on noise
		posJittered.y += data2d.height
		# Add jiggle to x and z based on noise
		posJittered.x += (
			data2d.noiseHeight.get_noise_2dv(Vector2(pos3d.z * voxelSize, pos3d.y * voxelSize))
			* 0.5
		)
		posJittered.z += (
			data2d.noiseHeight.get_noise_2dv(Vector2(pos3d.x * voxelSize, pos3d.y * voxelSize))
			* 0.5
		)

		return {
			"posJittered": posJittered,
			"roomDist3d": roomDist3d,
			"roomInside3d": roomInside3d,
		}


func _ready():
	# Initialise data generator
	var dataGen = DataGenerator.new()

	var nVoxels = 0

	var timeStart = Time.get_ticks_msec()

	# Create boxes within extents
	for x in range(-extents.x / voxelSize / 2, extents.x / voxelSize / 2):
		for z in range(-extents.z / voxelSize / 2, extents.z / voxelSize / 2):
			var pos2d = Vector2(x * voxelSize, z * voxelSize)

			# Get data for the 2d point
			var data2d = dataGen.get_data_2d(pos2d)

			if data2d.roomInside2d:
				for y in range(-extents.y / voxelSize / 2, extents.y / voxelSize / 2):
					var pos3d = Vector3(x * voxelSize, y * voxelSize, z * voxelSize)

					# Get data for the 3d point
					var data3d = dataGen.get_data_3d(data2d, pos2d, pos3d)

					# If inside the room, skip
					if data3d.roomInside3d:
						continue

					# Explore neighbouring voxels until we find one that is inside the room
					var adjacence = false
					for x2 in range(-1, 1):
						for y2 in range(-1, 1):
							for z2 in range(-1, 1):
								if x2 == 0 && y2 == 0 && z2 == 0:
									continue
								var pos2d2 = pos2d + Vector2(x2, z2) * voxelSize
								var pos3d2 = pos3d + Vector3(x2, y2, z2) * voxelSize
								var data3d2 = dataGen.get_data_3d(data2d, pos2d2, pos3d2)
								if data3d2.roomInside3d:
									adjacence = true
									break
							if adjacence:
								break
						if adjacence:
							break

					if adjacence:
						# Create a new BoxMesh
						var box = BoxMesh.new()
						box.size = Vector3(voxelSize, voxelSize, voxelSize)
						# Create a new MeshInstance
						var mesh = MeshInstance3D.new()
						mesh.mesh = box
						# Assign a random color to the box
						var shade = abs(pos3d.y) / 5
						var color = Color(shade, shade, shade)
						mesh.material_override = StandardMaterial3D.new()
						mesh.material_override.albedo_color = color
						# Position the mesh
						mesh.transform.origin = data3d.posJittered
						# Add mesh as a child of this node
						add_child(mesh)

						# Add collision shape
						# var shape = CollisionShape3D.new()
						# shape.shape = box
						# mesh.add_child(shape)

						# Increase voxel count
						nVoxels += 1

	print("Created ", nVoxels, " voxels")
	print("Time: ", Time.get_ticks_msec() - timeStart, " ms")
