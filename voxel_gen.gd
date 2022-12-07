extends Node3D

const chunkSize = 32.0
const largestVoxelSize = 2.0
const smallestVoxelSize = 0.25


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
		var roomAdjacence2d = roomDist < roomSizeLerp + 2

		return {
			"noiseHeight": noiseHeight,
			"height": height,
			"temperature": temperature,
			"roomAdjacence2d": roomAdjacence2d,
			"roomDist": roomDist,
			"roomSize": roomSizeLerp,
		}

	func get_data_3d(data2d, pos2d, pos3d):
		var data3d_roomInside = get_data_3d_roomInside(data2d, pos2d, pos3d)
		var roomWayOutside3d = data3d_roomInside.roomDist3d > data2d.roomSize + 2

		# Jitter the pos3d
		var posJittered = Vector3(pos3d.x, pos3d.y, pos3d.z)
		# Add height to y based on noise
		posJittered.y += data2d.height
		# Add jiggle to x and z based on noise
		posJittered.x += (data2d.noiseHeight.get_noise_2dv(Vector2(pos3d.z, pos3d.y)) * 0.5)
		posJittered.z += (data2d.noiseHeight.get_noise_2dv(Vector2(pos3d.x, pos3d.y)) * 0.5)

		# Get if voxel is floor or ceiling, if y close to 0 or above room height
		var isFloor = pos3d.y < -2
		var isCeiling = pos3d.y > 2
		var isHighCeiling = pos3d.y > 8

		return {
			"posJittered": posJittered,
			"roomDist3d": data3d_roomInside.roomDist3d,
			"roomInside3d": data3d_roomInside.roomInside3d,
			"roomWayOutside3d": roomWayOutside3d,
			"isFloor": isFloor,
			"isCeiling": isCeiling,
			"isHighCeiling": isHighCeiling,
		}

	func get_data_3d_roomInside(data2d, pos2d, pos3d):
		var roomHeight = 4 if pos3d.y < 0 else 2 + getNoise(0.1, 12345).get_noise_2dv(pos2d) * 0.5
		var roomDist3d = Vector3(pos3d.x, pos3d.y * roomHeight, pos3d.z).length()
		var roomInside3d = roomDist3d < data2d.roomSize
		return {
			"roomDist3d": roomDist3d,
			"roomInside3d": roomInside3d,
		}


var dataGen = DataGenerator.new()
var nVoxels = 0
var timeStart = Time.get_ticks_msec()


func renderVoxel(pos2d, pos3d, data2d, data3d, size):
	# Create a new BoxMesh
	var box = BoxMesh.new()
	box.size = Vector3(size, size, size)
	# Create a new MeshInstance
	var mesh = MeshInstance3D.new()
	mesh.mesh = box
	# Color from dark to light gray as height increases
	var shade = pos3d.y / 30
	var color = Color(0.5 + shade, 0.4 + shade, 0.3 + shade)
	# Give the color horizontal lines from noise to make it look more natural
	var noiseHeight = data2d.noiseHeight
	var noiseShade = noiseHeight.get_noise_1d(pos3d.y * 20 + pos3d.x * 0.01 + pos3d.z + 0.01) * 0.2
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
	mesh.transform.origin = posJittered
	# Add mesh as a child of this node
	add_child(mesh)

	# Add collision shape
	# var shape = CollisionShape3D.new()
	# shape.shape = box
	# mesh.add_child(shape)

	nVoxels += 1


# Subdivide a voxel into 8 smaller voxels, potentially subdivide those further
func subdivideVoxel(pos3d, voxelSize):
	# If voxel is too small, render it
	if voxelSize <= smallestVoxelSize:
		var pos2d = Vector2(pos3d.x, pos3d.z)
		var data2d = dataGen.get_data_2d(pos2d)
		var data3d = dataGen.get_data_3d(data2d, pos2d, pos3d)
		# If outside the room, render
		if not data3d.roomInside3d:
			renderVoxel(pos2d, pos3d, data2d, data3d, voxelSize)
		return

	if voxelSize <= largestVoxelSize:
		# Calculate how much of the voxel is air
		var nAirVoxels = 0
		var maxAirVoxels = 4 if voxelSize == 0.5 else 2 if voxelSize == 1 else 0
		for x in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				var pos2d = Vector2(pos3d.x + x * voxelSize, pos3d.z + z * voxelSize)
				var data2d = dataGen.get_data_2d(pos2d)
				for y in [-0.5, 0.5]:
					var data3d = dataGen.get_data_3d_roomInside(
						data2d, pos2d, pos3d + Vector3(x, y, z) * voxelSize
					)
					if data3d.roomInside3d:
						nAirVoxels += 1
						if nAirVoxels > maxAirVoxels:
							break
				if nAirVoxels > maxAirVoxels:
					break
			if nAirVoxels > maxAirVoxels:
				break
		# If air voxels in threshold range, render it
		if nAirVoxels <= maxAirVoxels:
			var pos2d = Vector2(pos3d.x, pos3d.z)
			var data2d = dataGen.get_data_2d(pos2d)
			var data3d = dataGen.get_data_3d(data2d, pos2d, pos3d)
			renderVoxel(pos2d, pos3d, data2d, data3d, voxelSize)
			return
	# Otherwise, subdivide it into 8 smaller voxels
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				var nVoxelSize = voxelSize / 2
				var pos2 = pos3d + Vector3(x, y, z) * nVoxelSize

				subdivideVoxel(pos2, nVoxelSize)


func _ready():
	subdivideVoxel(Vector3(0, 0, 0), chunkSize)

	print("Created ", nVoxels, " voxels")
	print("Time: ", Time.get_ticks_msec() - timeStart, " ms")

	# Await 5 seconds then create a new chunk
	# await get_tree().create_timer(5).timeout
	# subdivideVoxel(Vector3(chunkSize, 0, 0), chunkSize)
