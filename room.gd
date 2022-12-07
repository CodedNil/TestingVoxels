extends Node3D

const extents = Vector3(70, 35, 70)
const voxelSize = 0.5


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

		# Calculate if we are inside the room
		var roomAdjacence2d = roomDist < roomSizeLerp + voxelSize * 4

		return {
			"noiseHeight": noiseHeight,
			"height": height,
			"temperature": temperature,
			"roomAdjacence2d": roomAdjacence2d,
			"roomDist": roomDist,
			"roomSize": roomSizeLerp,
		}

	func get_data_3d(data2d, pos2d, pos3d):
		var roomHeight = 4 if pos3d.y < 0 else 2 + getNoise(0.1, 12345).get_noise_2dv(pos2d) * 0.5
		var roomDist3d = Vector3(pos3d.x, pos3d.y * roomHeight, pos3d.z).length()
		var roomInside3d = roomDist3d < data2d.roomSize
		var roomWayOutside3d = roomDist3d > data2d.roomSize + voxelSize * 4

		# Jitter the pos3d
		var posJittered = Vector3(pos3d.x, pos3d.y, pos3d.z)
		# Add height to y based on noise
		posJittered.y += data2d.height
		# Add jiggle to x and z based on noise
		posJittered.x += (
			data2d.noiseHeight.get_noise_2dv(Vector2(pos3d.z, pos3d.y))
			* 0.5
		)
		posJittered.z += (
			data2d.noiseHeight.get_noise_2dv(Vector2(pos3d.x, pos3d.y))
			* 0.5
		)

		# Get if voxel is floor or ceiling, if y close to 0 or above room height
		var isFloor = pos3d.y < -2
		var isCeiling = pos3d.y > 2
		var isHighCeiling = pos3d.y > 8

		return {
			"posJittered": posJittered,
			"roomDist3d": roomDist3d,
			"roomInside3d": roomInside3d,
			"roomWayOutside3d": roomWayOutside3d,
			"isFloor": isFloor,
			"isCeiling": isCeiling,
			"isHighCeiling": isHighCeiling,
		}

	func get_data_3d_roomInside(data2d, pos2d, pos3d):
		var roomHeight = 4 if pos3d.y < 0 else 2 + getNoise(0.1, 12345).get_noise_2dv(pos2d) * 1
		var roomDist3d = Vector3(pos3d.x, pos3d.y * roomHeight, pos3d.z).length()
		var roomInside3d = roomDist3d < data2d.roomSize
		return {
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

			if data2d.roomAdjacence2d:
				for y in range(-extents.y / voxelSize / 2, extents.y / voxelSize / 2):
					var pos3d = Vector3(x * voxelSize, y * voxelSize, z * voxelSize)

					# Get data for the 3d point
					var data3d = dataGen.get_data_3d(data2d, pos2d, pos3d)

					# If inside the room, skip
					if data3d.roomInside3d or data3d.roomWayOutside3d:
						continue

					# Explore neighbouring voxels until we find one that is inside the room
					# var adjacence = false
					# var searchExtents = [Vector3(-2, -2, -2), Vector3(2, 2, 2)]
					# if data3d.isFloor:
					# 	searchExtents = [Vector3(-2, -1, -2), Vector3(2, 3, 2)]
					# elif data3d.isCeiling:
					# 	searchExtents = [Vector3(-2, -4, -2), Vector3(2, 1, 2)]
					# if data3d.isHighCeiling:
					# 	searchExtents = [Vector3(-2, -5, -2), Vector3(2, 1, 2)]
					# for x2 in range(searchExtents[0].x, searchExtents[1].x + 1):
					# 	for y2 in range(searchExtents[0].y, searchExtents[1].y + 1):
					# 		for z2 in range(searchExtents[0].z, searchExtents[1].z+ 1):
					# 			if x2 == 0 && y2 == 0 && z2 == 0:
					# 				continue
					# 			var pos2d2 = pos2d + Vector2(x2, z2) * voxelSize
					# 			var pos3d2 = pos3d + Vector3(x2, y2, z2) * voxelSize
					# 			var data3d2 = dataGen.get_data_3d_roomInside(data2d, pos2d2, pos3d2)
					# 			if data3d2.roomInside3d:
					# 				adjacence = true
					# 				break
					# 		if adjacence:
					# 			break
					# 	if adjacence:
					# 		break
					
					# With adjacence
					# Created 147198 voxels
					# Time: 33769 ms

					# Without adjacence
					# Created 155964 voxels
					# Time: 26563 ms

					# Each time, look up repeatedly until it finds air, then merge all those y blocks into one and skip future calls
					# for y2 in range(5):
					# 	var pos3d2 = pos3d + Vector3(0, y2 * voxelSize, 0) 
					# 	var data3d2 = dataGen.get_data_3d_roomInside(data2d, pos2d, pos3d2)
					# 	if not data3d2.roomInside3d:
					# 		break
					# 	y = y2

					# if adjacence:
					# Create a new BoxMesh
					var box = BoxMesh.new()
					box.size = Vector3(voxelSize, voxelSize, voxelSize)
					# If is floor or ceiling, make it much taller
					if data3d.isFloor or data3d.isCeiling:
						box.size.y *= 10
					# Create a new MeshInstance
					var mesh = MeshInstance3D.new()
					mesh.mesh = box
					# Color from dark to light gray as height increases
					var shade = y / extents.y * 0.5
					var color = Color(0.5 + shade, 0.4 + shade, 0.3 + shade)
					# Give the color horizontal lines from noise to make it look more natural
					var noiseHeight = data2d.noiseHeight
					var noiseShade = noiseHeight.get_noise_1d(y * 20 + x * 0.01 + z + 0.01) * 0.2
					color += Color(noiseShade, noiseShade, noiseShade)
					# Add brown colors based on 2d noise
					var noiseColor = abs(noiseHeight.get_noise_2dv(pos2d * 0.1))
					color += Color(noiseColor, noiseColor * 0.5, 0) * 0.1
					# Add blue magic lines based on 3d noise
					if not data3d.isFloor:
						var noiseMagic = noiseHeight.get_noise_3dv(pos3d * 2)
						color += Color(0, 0, 1 if abs(noiseMagic) < 0.05 else 0)

					mesh.material_override = StandardMaterial3D.new()
					mesh.material_override.albedo_color = color
					# Position the mesh
					var posJittered = data3d.posJittered
					# If is floor or ceiling, make move it down or up
					if data3d.isFloor:
						posJittered.y -= voxelSize * 4
					if data3d.isCeiling:
						posJittered.y += voxelSize * 4
					mesh.transform.origin = posJittered
					# Add mesh as a child of this node
					add_child(mesh)

					# Add collision shape
					# var shape = CollisionShape3D.new()
					# shape.shape = box
					# mesh.add_child(shape)

					# Increase voxel count
					nVoxels += 1

		# Delay 0.1 seconds with await
		# await get_tree().create_timer(0.1).timeout
	
	print("Created ", nVoxels, " voxels")
	print("Time: ", Time.get_ticks_msec() - timeStart, " ms")
