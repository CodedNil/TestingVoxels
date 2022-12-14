extends Node3D

# Constants for chunk and voxel sizes
const chunkSize = 16.0
const largestVoxelSize = 4.0
const smallestVoxelSize = 0.25

# Get number of quality levels, based on the largest and smallest voxel size
var nQualityLevels = log(largestVoxelSize / smallestVoxelSize) / log(2)


# Create noise generator class that can be initialised then have functions within
class DataGenerator:
	# A function to get a noise value with given frequency and seed, caches the fastnoiselite
	var noises = {}

	# Voronoi noise creation

	# Procedural white noise
	func hash2(p):
		return Vector2(
			fposmod(sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0),
			fposmod(sin(p.dot(Vector2(269.5, 183.3))) * 43758.5453, 1.0)
		)

	func voronoi(p):
		var n = p.floor()
		var f = Vector2(fposmod(p.x, 1.0), fposmod(p.y, 1.0))

		# First pass: regular voronoi
		var mg = Vector2()
		var mr = Vector2()

		var md = 8.0
		for j in range(-1, 2):
			for i in range(-1, 2):
				var g = Vector2(i, j)
				var o = hash2(n + g)
				var r = g + o - f
				var d = r.dot(r)

				if d < md:
					md = d
					mr = r
					mg = g

		# Second pass: distance to borders
		md = 8.0
		for j in range(-2, 3):
			for i in range(-2, 3):
				var g = mg + Vector2(i, j)
				var o = hash2(n + g)
				var r = g + o - f

				if (mr - r).dot(mr - r) > 0.00001:
					md = min(md, (0.5 * (mr + r)).dot((r - mr).normalized()))

		return Vector3(md, mr.x, mr.y)

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

		# # Temperature scale, between 0 cold and 1 hot
		# var temperature = 0.5 + getNoise(0.03, 1234).get_noise_2dv(pos2d) * 0.5

		# # Get data for the room
		# # Get angle from center with x and z, from -pi to pi
		# var roomAngle = pos2d.angle_to_point(Vector2(0, 0))
		# # Get 2d distance from center with x and z
		# var roomDist = pos2d.length()

		# Get voronoi noise at location
		var voronoiNoise = voronoi(pos2d * 0.1)

		# # Calculate room size, based on noise from the angle
		# var roomSize0 = 20 + getNoise(0.3, 123).get_noise_1d(-PI) * 20
		# var roomSize = 20 + getNoise(0.3, 123).get_noise_1d(roomAngle) * 20
		# # For the last 25% of the angle, so from half pi to pi, lerp towards roomSize0
		# var roomSizeLerp = (
		# 	lerp(roomSize, roomSize0, (roomAngle - PI / 2) / (PI / 2))
		# 	if roomAngle > PI / 2
		# 	else roomSize
		# )

		# # Calculate if we are inside the room
		# var roomAdjacence2d = roomDist < roomSizeLerp + 2

		return {
			"noiseHeight": noiseHeight,
			"height": height,
			# "temperature": temperature,
			# "roomAdjacence2d": roomAdjacence2d,
			# "roomDist": roomDist,
			# "roomSize": roomSizeLerp,
			"voronoiNoise": voronoiNoise,
		}

	func get_data_3d(data2d, pos2d, pos3d):
		var data3d_roomInside = get_data_3d_roomInside(data2d, pos2d, pos3d)

		# Jitter the pos3d
		var posJittered = Vector3(pos3d.x, pos3d.y, pos3d.z)
		# Add height to y based on noise
		posJittered.y += data2d.height
		# Add jiggle to x and z based on noise
		posJittered.x += (data2d.noiseHeight.get_noise_2dv(Vector2(pos3d.z, pos3d.y)) * 0.5)
		posJittered.z += (data2d.noiseHeight.get_noise_2dv(Vector2(pos3d.x, pos3d.y)) * 0.5)

		# Get if voxel is floor or ceiling, if y close to 0 or above room height
		var isFloor = pos3d.y < -2

		return {
			"posJittered": posJittered,
			"roomInside3d": data3d_roomInside.roomInside3d,
			"isFloor": isFloor,
		}

	func get_data_3d_roomInside(data2d, pos2d, pos3d):
		# var roomHeight = 4 if pos3d.y < 0 else 2 + getNoise(0.1, 12345).get_noise_2dv(pos2d) * 0.5
		# var roomDist3d = Vector3(pos3d.x, pos3d.y * roomHeight, pos3d.z).length()
		# var roomInside3d = roomDist3d < data2d.roomSize
		
		var newRoomInside = data2d.voronoiNoise.x > 0.07

		return {
			# "roomDist3d": roomDist3d,
			"roomInside3d": newRoomInside,
		}


# Chunk class
class Chunk extends Node3D:
	var dataGen = DataGenerator.new()
	
	var pos = Vector3(0, 0, 0)
	var nCubes = 0
	# Store the cubes at each division level
	var cubes = {}
	var meshes = []
	var multiMeshes = {}
	# Chunks current subdivision level
	var subdivisionLevel = 0
	var chunksVoxelSize = largestVoxelSize

	# Hold back subdivisions until you get closer
	var heldSubdivisons = []

	# Create a chunk at a position
	func _init(pos):
		self.pos = pos
		# Create multi meshes for each subdivision level
		var cVoxelSize = chunkSize
		while cVoxelSize > smallestVoxelSize:
			cVoxelSize /= 2
	
			if cVoxelSize <= largestVoxelSize:
				# Create the multi mesh instance
				var multiMesh = MultiMesh.new()
				multiMesh.transform_format = MultiMesh.TRANSFORM_3D
				multiMesh.use_colors = true
				multiMesh.use_custom_data  = false
				multiMesh.instance_count = 100000
				multiMesh.mesh = BoxMesh.new()
				multiMesh.mesh.size = Vector3(cVoxelSize, cVoxelSize, cVoxelSize)
				var meshInstance = MultiMeshInstance3D.new()
				meshInstance.multimesh = multiMesh
				# Add material
				meshInstance.material_override = StandardMaterial3D.new()
				meshInstance.material_override.albedo_color = Color(1, 1, 1)
				meshInstance.material_override.vertex_color_use_as_albedo = true
				# Add to scene
				add_child(meshInstance)
				multiMeshes[cVoxelSize] = [multiMesh]
		
		# Create the first subdivision
		subdivideVoxel(pos, chunkSize)
		rerenderMultiMeshes()

	func rerenderMultiMeshes():
		# Count number of voxels at each size, and set instance count, and create the meshes
		for size in multiMeshes:
			if multiMeshes[size][0].instance_count != len(multiMeshes[size]):
				multiMeshes[size][0].instance_count = len(multiMeshes[size])
				for i in range(len(multiMeshes[size])):
					if i > 0:
						multiMeshes[size][0].set_instance_transform(i, Transform3D(Basis(), multiMeshes[size][i][0]))
						multiMeshes[size][0].set_instance_color(i, multiMeshes[size][i][1])


	func renderVoxel(pos2d, pos3d, data2d, data3d, size):
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

		# Add mesh to multi mesh
		multiMeshes[size].append([data3d.posJittered, color])

		# Add collision shape
		# var shape = CollisionShape3D.new()
		# shape.shape = box
		# mesh.add_child(shape)

		nCubes += 1
	
	# Subdivide a voxel into 8 smaller voxels, potentially subdivide those further
	func subdivideVoxel(pos3d, voxelSize):
		# Add count
		if voxelSize not in cubes:
			cubes[voxelSize] = 0
		cubes[voxelSize] += 1

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
			# If air voxels in threshold range, render it
			if nAirVoxels <= maxAirVoxels:
				var pos2d = Vector2(pos3d.x, pos3d.z)
				var data2d = dataGen.get_data_2d(pos2d)
				var data3d = dataGen.get_data_3d(data2d, pos2d, pos3d)
				renderVoxel(pos2d, pos3d, data2d, data3d, voxelSize)
				return
			# If fully air, skip
			if nAirVoxels == 8:
				return
		# Otherwise, subdivide it into 8 smaller voxels
		for x in [-0.5, 0.5]:
			for y in [-0.5, 0.5]:
				for z in [-0.5, 0.5]:
					var nVoxelSize = voxelSize / 2
					var pos2 = pos3d + Vector3(x, y, z) * nVoxelSize

					# Temporarily only respsect y == 0
					if nVoxelSize < 4 and abs(pos2.y) > 1:
						continue

					# Hold back some subdivisions to render later
					if nVoxelSize < chunksVoxelSize:
						heldSubdivisons.append([pos2, nVoxelSize])
					else:
						subdivideVoxel(pos2, nVoxelSize)

	# Release subdivisions, if any
	func releaseSubdivisionsRun():
		var newHelds = []
		for subdivision in heldSubdivisons:
			if subdivision[1] < chunksVoxelSize:
				newHelds.append(subdivision)
			else:
				subdivideVoxel(subdivision[0], subdivision[1])
		heldSubdivisons = newHelds

	func releaseSubdivisions(newVoxelSize):
		if heldSubdivisons.size() == 0:
			return
		chunksVoxelSize = newVoxelSize
		releaseSubdivisionsRun()
		rerenderMultiMeshes()


var chunks = {}
const renderDistance = 2
func _process(delta):
	# Find chunks near the camera that need to be created
	var camera = get_parent().get_node("Camera3D")
	var cameraPos = camera.global_transform.origin
	
	var cameraChunkPos = Vector3(
		floor(cameraPos.x / chunkSize) * chunkSize,
		floor(cameraPos.y / chunkSize) * chunkSize,
		floor(cameraPos.z / chunkSize) * chunkSize
	)
	for x in range(-renderDistance, renderDistance + 1):
		for y in range(-renderDistance, renderDistance + 1):
			for z in range(-renderDistance, renderDistance + 1):
				# Get chunks distance for quality level
				var chunkDistance = Vector3(x, y, z).length()

				var renderChunkPos = cameraChunkPos + Vector3(x, y, z) * chunkSize
				# if renderChunkPos.x > 0:
				var chunk = chunks.get(renderChunkPos)
				if chunk == null:
					chunk = Chunk.new(renderChunkPos)
					add_child(chunk)
					chunks[renderChunkPos] = chunk
				else:
					# Update the chunks subdivisionLevel up to max nQualityLevel, based on how close it is to the camera
					chunk.subdivisionLevel = min(nQualityLevels, round(nQualityLevels - chunkDistance))
					# Update the chunksVoxelSize, starts at largestVoxelSize then halved each subdivision
					var newVoxelSize = largestVoxelSize / pow(2, chunk.subdivisionLevel)
					if chunk.chunksVoxelSize != newVoxelSize:
						# Release held subdivisions
						chunk.releaseSubdivisions(newVoxelSize)
	
	# Remove chunks that are too far away
	for chunkPos in chunks:
		if chunkPos.distance_to(cameraPos) > chunkSize * renderDistance * 2:
			chunks[chunkPos].queue_free()
			chunks.erase(chunkPos)
