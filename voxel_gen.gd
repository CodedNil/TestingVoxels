extends Node3D

const chunkSize: float = 16.0
const largestVoxelSize: float = 4.0
const smallestVoxelSize: float = 0.25

const roomSpacing: float = 70

const renderDistance: int = 24

const msBudget: float = 12  # Max time to spend on subdivision per update frame

# Get number of quality levels, based on the largest and smallest voxel size
const nQualityLevels: int = int(log(largestVoxelSize / smallestVoxelSize) / log(2))


# Create noise generator class that can be initialised then have functions within
class DataGenerator:
	# A function to get a noise value with given frequency and seed, caches the fastnoiselite
	var noises: Dictionary = {}

	func getNoise(frequency, nseed):
		var key: String = str(frequency) + ";" + str(nseed)
		if key in noises:
			return noises[key]
		else:
			var noise: FastNoiseLite = FastNoiseLite.new()
			noise.frequency = frequency
			noise.seed = nseed
			noises[key] = noise
			return noise

	# Get data for a 2d point in the world
	func get_data_2d(pos2d):
		# Base world variables
		# World height offset for nice gradient slopes, -2 to 2, could have caves going uphill or downhill
		var worldNoise: FastNoiseLite = getNoise(0.03, 1234)
		var height: float = worldNoise.get_noise_2dv(pos2d / 10) * 10
		# Temperature scale, between 0 cold and 1 hot
		var temperature: float = 0.5 + worldNoise.get_noise_2dv(pos2d) * 0.5
		# Humidity scale, between 0 dry and 1 wet
		var humidity: float = 0.5 + worldNoise.get_noise_2dv(pos2d) * 0.5
		# Lushness scale, between 0 barren and 1 lush
		var lushness: float = 0.5 + worldNoise.get_noise_2dv(pos2d) * 0.5

		# Get position offset by noise, so it is not on a perfect grid
		var horizontalOffset = Vector2(
			worldNoise.get_noise_1d(pos2d.y / 4) * 60,
			worldNoise.get_noise_1d(pos2d.x / 4) * 60,
		)

		# Get data for the room
		# Get 2d room center position, pos2d snapped to nearest room spacing point
		var roomPosition: Vector2 = Vector2(
			round(pos2d.x / roomSpacing) * roomSpacing,
			round(pos2d.y / roomSpacing) * roomSpacing
		) + horizontalOffset
		# Get room noise seed, based on room position
		var roomSeed: float = roomPosition.x + roomPosition.y * 123
		# Get angle from center with x and z, from -pi to pi
		var roomAngle: float = pos2d.angle_to_point(roomPosition)
		# Get 2d distance from center with x and z
		var roomDist: float = pos2d.distance_to(roomPosition)

		# Calculate room size, based on noise from the angle
		var roomBaseSize: float = 15 + worldNoise.get_noise_1d(roomSeed) * 15
		var roomSize0: float = roomBaseSize + getNoise(0.3, roomSeed).get_noise_1d(-PI) * roomBaseSize
		var roomSize: float = roomBaseSize + getNoise(0.3, roomSeed).get_noise_1d(roomAngle) * roomBaseSize
		# For the last 25% of the angle, so from half pi to pi, lerp towards roomSize0
		var roomSizeLerp: float = (
			lerp(roomSize, roomSize0, (roomAngle - PI / 2) / (PI / 2))
			if roomAngle > PI / 2
			else roomSize
		)

		# Get data for the corridors
		var corridorWidth: float = 6 + worldNoise.get_noise_2dv(pos2d) * 8
		var corridorDist: float = min(
			abs(pos2d.x + worldNoise.get_noise_1d(pos2d.y) * 8 - roomPosition.x),
			abs(pos2d.y + worldNoise.get_noise_1d(pos2d.x) * 8 - roomPosition.y),
		)

		return {
			"worldNoise": worldNoise,
			"height": height,
			"temperature": temperature,
			"humidity": humidity,
			"lushness": lushness,
			"roomPosition": roomPosition,
			"roomDist": roomDist,
			"roomSize": roomSizeLerp,
			"corridorWidth": corridorWidth,
			"corridorDist": corridorDist,
		}

	func get_data_3d(data2d, pos2d, pos3d):
		var roomHeight: float = 4 if pos3d.y < 0 else 2 + getNoise(0.1, 12345).get_noise_2dv(pos2d) * 0.5
		var roomDist3d: float = Vector3(pos3d.x - data2d.roomPosition.x, pos3d.y * roomHeight, pos3d.z - data2d.roomPosition.y).length()
		var roomInside3d: bool = roomDist3d < data2d.roomSize

		var corridorHeight: float = 4 if pos3d.y < 0 else 2 + getNoise(0.1, 12345).get_noise_2dv(pos2d) * 0.5
		var corridorDist3d: float = Vector2(data2d.corridorDist, pos3d.y * corridorHeight / 2).length()
		var corridorInside3d: bool = corridorDist3d < data2d.corridorWidth

		var inside3d: bool = roomInside3d or corridorInside3d
		return {
			"roomDist3d": roomDist3d,
			"inside3d": inside3d,
		}

	func get_data_3d_advanced(data2d, pos2d, pos3d):
		var data3d: Dictionary = get_data_3d(data2d, pos2d, pos3d)

		# Jitter the pos3d
		var posJittered: Vector3 = Vector3(pos3d.x, pos3d.y, pos3d.z)
		# Add height to y based on noise
		posJittered.y += data2d.height
		# Add jiggle to x and z based on noise
		posJittered.x += (data2d.worldNoise.get_noise_2dv(Vector2(pos3d.z, pos3d.y)) * 0.5)
		posJittered.z += (data2d.worldNoise.get_noise_2dv(Vector2(pos3d.x, pos3d.y)) * 0.5)

		return {
			"posJittered": posJittered,
			"roomDist3d": data3d.roomDist3d,
			"inside3d": data3d.inside3d,
		}

# Define the materials
var voxelMaterials: Dictionary = {}
func _ready():
	# Standard
	voxelMaterials['standard'] = StandardMaterial3D.new()
	voxelMaterials['standard'].albedo_color = Color(1, 1, 1)
	voxelMaterials['standard'].vertex_color_use_as_albedo = true
	voxelMaterials['standard'].shading_mode = StandardMaterial3D.SHADING_MODE_PER_VERTEX
	voxelMaterials['standard'].roughness = 1
	# Blue magic
	voxelMaterials['bluemagic'] = StandardMaterial3D.new()
	voxelMaterials['bluemagic'].albedo_color = Color(1, 1, 1)
	voxelMaterials['bluemagic'].vertex_color_use_as_albedo = true
	voxelMaterials['bluemagic'].shading_mode = StandardMaterial3D.SHADING_MODE_PER_VERTEX
	voxelMaterials['bluemagic'].emission_enabled = true
	voxelMaterials['bluemagic'].emission_energy = 1
	voxelMaterials['bluemagic'].emission = Color(0, 0, 0.5)
	voxelMaterials['bluemagic'].rim_enabled = true
	voxelMaterials['bluemagic'].rim = 1
	voxelMaterials['bluemagic'].rim_tint = 0.5


# Chunk class
class Chunk:
	extends Node3D
	var dataGen: DataGenerator = DataGenerator.new()

	var pos: Vector3 = Vector3(0, 0, 0)  # Chunks position
	var multiMeshes: Dictionary = {}  # Store the cubes at each division level
	var chunksVoxelSize: float = largestVoxelSize  # Chunks current subdivision level

	# Hold back subdivisions until you get closer, or to prevent lag
	var progressSubdivisions: Array = []
	var heldSubdivisons: Array = []

	# Create a chunk at a position
	func _init(initPos):
		pos = initPos
	
	# Create the meshes for the chunk
	func initMeshes():
		# Create multi meshes for each subdivision level
		var cVoxelSize: float = chunkSize
		while cVoxelSize > smallestVoxelSize:
			cVoxelSize /= 2

			if cVoxelSize <= largestVoxelSize:
				# Create the multi mesh instances per material
				var meshes = {}
				var materials = get_parent().voxelMaterials
				for material in materials:
					var multiMesh: MultiMesh = MultiMesh.new()
					multiMesh.transform_format = MultiMesh.TRANSFORM_3D
					multiMesh.use_colors = true
					multiMesh.use_custom_data = false
					multiMesh.instance_count = 0
					multiMesh.mesh = BoxMesh.new()
					multiMesh.mesh.size = Vector3(cVoxelSize, cVoxelSize, cVoxelSize)
					var meshInstance: MultiMeshInstance3D = MultiMeshInstance3D.new()
					meshInstance.multimesh = multiMesh
					# Add material
					meshInstance.material_override = materials[material]
					# Add to scene
					add_child(meshInstance)
					# Add to array
					meshes[material] = [multiMesh, []]
				# Add all arrays to the multiMeshes array
				multiMeshes[cVoxelSize] = meshes

		# Create the first subdivision
		subdivideVoxel(pos, chunkSize)
		rerenderMultiMeshes()

	func rerenderMultiMeshes():
		# Count number of voxels at each size, and set instance count, and create the meshes
		for size in multiMeshes:
			for material in multiMeshes[size]:
				var mesh = multiMeshes[size][material][0]
				var meshArray = multiMeshes[size][material][1]
				if mesh.instance_count != len(meshArray):
					mesh.instance_count = len(meshArray)
					for i in range(len(meshArray)):
						mesh.set_instance_transform(i, Transform3D(Basis(), meshArray[i][0]))
						mesh.set_instance_color(i, meshArray[i][1])

	func renderVoxel(pos2d, pos3d, data2d, data3d, size):
		# Color from dark to light gray as height increases
		var shade: float = pos3d.y / 30
		var color: Color = Color(0.5 + shade, 0.4 + shade, 0.3 + shade)
		var material: String = 'standard'
		# Give the color horizontal lines from noise to make it look more natural
		var noiseShade: float = (
			data2d.worldNoise.get_noise_1d(pos3d.y * 20 + pos3d.x * 0.01 + pos3d.z + 0.01)
			* 0.2
		)
		color += Color(noiseShade, noiseShade, noiseShade)
		# Add brown colors based on 2d noise
		var noiseColor: float = abs(data2d.worldNoise.get_noise_2dv(pos2d * 0.1))
		color += Color(noiseColor, noiseColor * 0.5, 0) * 0.1
		# Add blue magic lines based on 3d noise
		if pos3d.y > -2:
			var noiseMagic: float = data2d.worldNoise.get_noise_3dv(pos3d * 2)
			if abs(noiseMagic) < 0.05:
				color = color * 0.1 + Color(0, 0, 1 - abs(noiseMagic) * 10)
				material = 'bluemagic'

		# Add mesh to multi mesh
		multiMeshes[size][material][1].append([data3d.posJittered, color])

		# Add collision shape
		# if size >= 0.5:
		# 	var shape: CollisionShape3D = CollisionShape3D.new()
		# 	shape.shape = box
		# 	mesh.add_child(shape)

	# Subdivide a voxel into 8 smaller voxels, potentially subdivide those further
	func subdivideVoxel(pos3d, voxelSize):
		# If voxel is too small, render it
		if voxelSize <= smallestVoxelSize:
			var pos2d: Vector2 = Vector2(pos3d.x, pos3d.z)
			var data2d: Dictionary = dataGen.get_data_2d(pos2d)
			var data3d: Dictionary = dataGen.get_data_3d_advanced(data2d, pos2d, pos3d)
			# If outside the room, render
			if not data3d.inside3d:
				renderVoxel(pos2d, pos3d, data2d, data3d, voxelSize)
			return

		if voxelSize <= largestVoxelSize:
			# Calculate how much of the voxel is air
			var nAirVoxels: int = 0
			# Smaller voxels have higher threshold for air, so less small voxels made
			var maxAirVoxels: int = 4 if voxelSize == 0.5 else 2 if voxelSize == 1 else 0
			for x in [-0.5, 0.5]:
				for z in [-0.5, 0.5]:
					var pos2d: Vector2 = Vector2(pos3d.x + x * voxelSize, pos3d.z + z * voxelSize)
					var data2d: Dictionary = dataGen.get_data_2d(pos2d)
					for y in [-0.5, 0.5]:
						var data3d: Dictionary = dataGen.get_data_3d(
							data2d, pos2d, pos3d + Vector3(x, y, z) * voxelSize
						)
						if data3d.inside3d:
							nAirVoxels += 1
			# If air voxels in threshold range, render it
			if nAirVoxels <= maxAirVoxels:
				var pos2d: Vector2 = Vector2(pos3d.x, pos3d.z)
				var data2d: Dictionary = dataGen.get_data_2d(pos2d)
				var data3d: Dictionary = dataGen.get_data_3d_advanced(data2d, pos2d, pos3d)
				renderVoxel(pos2d, pos3d, data2d, data3d, voxelSize)
				return
			# If fully air, skip
			if nAirVoxels == 8:
				return
		# Otherwise, subdivide it into 8 smaller voxels
		for x in [-0.5, 0.5]:
			for y in [-0.5, 0.5]:
				for z in [-0.5, 0.5]:
					var nVoxelSize: float = voxelSize / 2
					var pos2: Vector3 = pos3d + Vector3(x, y, z) * nVoxelSize

					# Hold back some subdivisions to render later
					if nVoxelSize < chunksVoxelSize:
						heldSubdivisons.append([pos2, nVoxelSize])
					else:
						progressSubdivisions.append([pos2, nVoxelSize])

	# Progress on subdivisions
	func progress(startTime):
		var newProgress: Array = []
		for subdivision in progressSubdivisions:
			# Try to maintain a good framerate
			if Time.get_ticks_msec() - startTime > msBudget:
				newProgress.append(subdivision)
			else:
				subdivideVoxel(subdivision[0], subdivision[1])
		progressSubdivisions = newProgress
		rerenderMultiMeshes()

	# Release subdivisions
	func releaseSubdivisions(newVoxelSize):
		chunksVoxelSize = newVoxelSize
		progressSubdivisions += heldSubdivisons
		heldSubdivisons = []


var chunks: Dictionary = {}

func sortDescending(a, b):
	if a[0] > b[0]:
		return true
	return false

func _process(_delta):
	# Get time to calculate ms budget
	var startTime: float = Time.get_ticks_msec()

	# Find chunks near the camera that need to be created
	var camera: Node3D = get_parent().get_node("Camera3D")
	var cameraPos: Vector3 = camera.global_transform.origin

	var cameraChunkPos: Vector3 = Vector3(
		floor(cameraPos.x / chunkSize) * chunkSize,
		floor(cameraPos.y / chunkSize) * chunkSize,
		floor(cameraPos.z / chunkSize) * chunkSize
	)

	# Only update one chunk per frame max
	var chunkToProgress: Array = []
	var renderDists: Array = [0]
	for dist in range(1, renderDistance):
		renderDists.append(dist)
		renderDists.append(-dist)
	
	# Loop through chunks in a spiral pattern
	var hRD: float = float(renderDistance) / 2
	var x: float = 0
	var z: float = 0
	var dx: float = 0
	var dz: float = -1
	for i in range(renderDistance**2):
		if (-hRD <= x and x <= hRD) and (-hRD <= z and z <= hRD):
			# Get chunk position
			for y in [0, -1, 1]:
				# Get chunks distance for quality level
				var chunkDistance: float = Vector3(x, y, z).length()
				# Ignore chunks in a radius outside the render distance
				if chunkDistance > float(renderDistance) / 2:
					continue

				var renderChunkPos: Vector3 = Vector3(cameraChunkPos.x + x * chunkSize, y * chunkSize, cameraChunkPos.z + z * chunkSize)

				var chunk: Chunk = chunks.get(renderChunkPos)
				if chunk == null:
					chunk = Chunk.new(renderChunkPos)
					add_child(chunk)
					chunk.initMeshes()
					chunks[renderChunkPos] = chunk
				else:
					# Get the chunks minimum voxel size, based on how close it is to the camera, halved from max each time
					var subdivisionLevel: int = clamp(
						round(nQualityLevels - chunkDistance + 1), 0, nQualityLevels
					)
					var newVoxelSize: float = largestVoxelSize / pow(2, subdivisionLevel)

					if chunk.progressSubdivisions.size() != 0:
						# Calculate progress priority, based on distance from camera and if it is in front of the camera
						var cameraDir: Vector3 = camera.global_transform.basis.z
						var chunkDir: Vector3 = (renderChunkPos - cameraPos).normalized()
						var dot: float = cameraDir.dot(chunkDir)
						var priority: float = chunkDistance + dot * 2 - chunk.chunksVoxelSize
						chunkToProgress.append([priority, chunk])
					# Release subdivisions if the voxel size is too big
					if (chunk.chunksVoxelSize != newVoxelSize and chunk.heldSubdivisons.size() != 0 and chunk.progressSubdivisions.size() == 0):
						chunk.releaseSubdivisions(chunk.chunksVoxelSize / 2)
		# Rotate the spiral
		if (x == z) or (x < 0 and x == -z) or (x > 0 and x == 1 - z):
			var t: float = dx
			dx = -dz
			dz = t
		x += dx
		z += dz

	# Sort chunks by priority
	chunkToProgress.sort_custom(sortDescending)
	# Perhaps do the entire above only once every x seconds (or if chunkToProgress is empty)

	# Progress on priority chunk
	if chunkToProgress.size() != 0:
		for i in range(20):
			var chunk: Array = chunkToProgress.pop_back()
			chunk[1].progress(startTime)
			# Try to maintain a good framerate
			if Time.get_ticks_msec() - startTime > msBudget:
				break
			if chunkToProgress.size() == 0:
				break

	# Remove chunks that are too far away
	var totalVoxels: int = 0
	var totalMeshes: int = 0
	for chunkPos in chunks:
		if chunkPos.distance_to(cameraPos) > renderDistance * chunkSize:
			chunks[chunkPos].queue_free()
			chunks.erase(chunkPos)
		else:
			for size in chunks[chunkPos].multiMeshes:
				for material in chunks[chunkPos].multiMeshes[size]:
					var mesh = chunks[chunkPos].multiMeshes[size][material][0]
					totalMeshes += 1
					totalVoxels += mesh.instance_count

	# Print stats
	var message: Array = []
	message.append("FPS: " + str(Engine.get_frames_per_second()))
	message.append("Total voxels: " + str(totalVoxels))
	message.append("Total meshes: " + str(totalMeshes))
	message.append("Total chunks: " + str(chunks.size()))
	print('\n'.join(message))