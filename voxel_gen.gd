extends Node3D

const chunkSize: float = 16.0
const largestVoxelSize: float = 8.0
const smallestVoxelSize: float = 0.25

const roomSpacing: float = 60

const renderDistance: int = 24

const msBudget: float = 30  # Max time to spend on subdivision per update frame

# Get number of quality levels, based on the largest and smallest voxel size
const nQualityLevels: int = int(log(largestVoxelSize / smallestVoxelSize) / log(2))


# Create noise generator class that can be initialised then have functions within
class DataGenerator:
	var worldNoise: FastNoiseLite = FastNoiseLite.new()
	func _init() -> void:
		worldNoise.frequency = 0.03
		worldNoise.seed = 1234
	
	# Get a noise value clamped from 0 to 1, but the noise is scaled up to clamp extreme values
	func getWorldsNoise(offset: float, pos2d: Vector2, scale: float) -> float:
		return clamp((1 + worldNoise.get_noise_3d(offset * 1000, pos2d.x * scale, pos2d.y * scale) * 1.4) * 0.5, 0, 1)

	# Get data for a point in the world
	var cachedData2d: Dictionary = {}
	var cachedData3d: Dictionary = {}
	func get_data_2d(pos2d: Vector2) -> Dictionary:
		# Check if data is cached
		if pos2d in cachedData2d:
			return cachedData2d[pos2d]

		# Base world variables
		# World elevation offset for nice gradient slopes, -2 to 2, could have caves going uphill or downhill
		var elevation: float = worldNoise.get_noise_2dv(pos2d / 10) * 10
		# Smoothness scale, between 0 and 1, 0 is flat, 1 is smooth
		var smoothness: float = getWorldsNoise(0, pos2d, 0.1)
		# Temperature scale, between 0 cold and 1 hot
		var temperature: float = getWorldsNoise(1, pos2d, 0.1)
		# Humidity scale, between 0 dry and 1 wet
		var humidity: float = getWorldsNoise(2, pos2d, 0.1)
		# Lushness scale, between 0 barren and 1 lush
		var lushness: float = getWorldsNoise(3, pos2d, 0.1)
		# Development scale, between 0 undeveloped and 1 developed
		var development: float = getWorldsNoise(4, pos2d, 0.1)

		# Get position offset by noise, so it is not on a perfect grid
		var horizontalOffset = Vector2(
			worldNoise.get_noise_1d(pos2d.y / 4) * (roomSpacing / 2),
			worldNoise.get_noise_1d(pos2d.x / 4) * (roomSpacing / 2)
		)

		# Get data for the room
		# Get 2d room center position, pos2d snapped to nearest room spacing point
		var roomPosition: Vector2 = Vector2(
			round(pos2d.x / roomSpacing) * roomSpacing,
			round(pos2d.y / roomSpacing) * roomSpacing
		)
		# Get room noise seed, based on room position
		var roomSeed: float = roomPosition.x + roomPosition.y * 123
		roomPosition += horizontalOffset
		# Get angle from center with x and z, from -pi to pi
		var roomAngle: float = pos2d.angle_to_point(roomPosition)
		# Get 2d distance from center with x and z
		var roomDist: float = pos2d.distance_to(roomPosition)

		# Calculate room size, based on noise from the angle
		var roomBaseSize: float = lerp(15, 20, smoothness) + worldNoise.get_noise_1d(roomSeed) * lerp(15, 2, smoothness)
		var roomSizeNoise = 5 + (1 - smoothness) * 30
		var roomSize0: float = roomBaseSize + worldNoise.get_noise_2d(roomSeed, -PI * roomSizeNoise) * roomBaseSize / 2
		var roomSize: float = roomBaseSize + worldNoise.get_noise_2d(roomSeed, roomAngle * roomSizeNoise) * roomBaseSize / 2
		# For the last 25% of the angle, so from half pi to pi, lerp towards roomSize0
		var roomSizeLerp: float = (
			lerp(roomSize, roomSize0, (roomAngle - PI / 2) / (PI / 2))
			if roomAngle > PI / 2
			else roomSize
		)

		# Get data for the corridors
		var corridorWidth: float = 6 + worldNoise.get_noise_2dv(pos2d) * 4
		var corridorDist: float = min(
			abs(pos2d.x + worldNoise.get_noise_1d(pos2d.y) * 8 - roomPosition.x),
			abs(pos2d.y + worldNoise.get_noise_1d(pos2d.x) * 8 - roomPosition.y),
		)

		# Get room height data
		var roomFloor: float = 4 + worldNoise.get_noise_2dv(pos2d * lerp(4, 1, smoothness)) * lerp(2.0, 0.5, smoothness)
		var roomCeiling: float = 2 + worldNoise.get_noise_2dv(pos2d * lerp(20, 3, smoothness)) * lerp(2.0, 0.5, smoothness)

		var data2d: Dictionary = {
			"elevation": elevation,
			"smoothness": smoothness,
			"temperature": temperature,
			"humidity": humidity,
			"lushness": lushness,
			"development": development,
			"roomFloor": roomFloor,
			"roomCeiling": roomCeiling,
			"roomPosition": roomPosition,
			"roomDist": roomDist,
			"roomSize": roomSizeLerp,
			"corridorWidth": corridorWidth,
			"corridorDist": corridorDist,
		}
		cachedData2d[pos2d] = data2d
		return data2d

	func get_data_3d(data2d: Dictionary, pos3d: Vector3) -> bool:
		# Check if data is cached
		if pos3d in cachedData3d:
			return cachedData3d[pos3d]

		var roomHeightSmooth: float = data2d.roomFloor if pos3d.y < 0 else data2d.roomCeiling

		var roomDist3d: float = Vector3(pos3d.x - data2d.roomPosition.x, pos3d.y * roomHeightSmooth, pos3d.z - data2d.roomPosition.y).length()
		var roomInside3d: bool = roomDist3d < data2d.roomSize

		var corridorDist3d: float = Vector2(data2d.corridorDist, pos3d.y * roomHeightSmooth / 2.0).length()
		var corridorInside3d: bool = corridorDist3d < data2d.corridorWidth

		var inside3d: bool = roomInside3d or corridorInside3d
		cachedData3d[pos3d] = inside3d
		return inside3d
	
	func get_data_color(pos2d: Vector2, pos3d: Vector3, data2d: Dictionary, size: float) -> Dictionary:
		# Color from dark to light gray as elevation increases
		var shade: float = pos3d.y / 30
		var color: Color = Color(0.5 + shade, 0.4 + shade, 0.3 + shade)
		var material: String = 'standard'
		
		# Give the color horizontal lines from noise to make it look more natural
		var noiseShade: float = (0.5 + worldNoise.get_noise_1d(pos3d.y * 20 + pos3d.x * 0.01 + pos3d.z + 0.01) / 2) * 0.2
		color += Color(noiseShade, noiseShade, noiseShade)
		# Add brown colors based on 2d noise
		var noiseColor: float = 0.5 + worldNoise.get_noise_2dv(pos2d * 0.1) / 2
		color += Color(noiseColor, noiseColor * 0.5, 0) * 0.1

		# Add blue magic lines based on 3d noise
		if pos3d.y > -2 and size <= 1:
			var noiseMagic: float = worldNoise.get_noise_3dv(pos3d * 2)
			if abs(noiseMagic) < 0.05:
				color = color * 0.1 + Color(0, 0, 1 - abs(noiseMagic) * 10)
				material = 'bluemagic'

		# Add color on floors
		if pos3d.y < (data2d.roomFloor - 4) * 4 - 2:
			# Slight offset on the noise to make it look more natural
			var noiseOffset: float = worldNoise.get_noise_2dv(pos2d * 20) * 0.02

			# Use sand color if temperature is high and humidity low
			if data2d.temperature > 0.7 + noiseOffset and data2d.humidity < 0.3 + noiseOffset and material == 'standard':
				var colorVariance: float = worldNoise.get_noise_2dv(pos2d * 2) * 0.15
				color = Color(1 + colorVariance, 0.9 + colorVariance, 0.6 + colorVariance)
			# Use grass color if humidity high
			if data2d.humidity > 0.5 + noiseOffset and material == 'standard':
				var colorVariance: float = worldNoise.get_noise_2dv(pos2d * 2) * 0.15
				color = lerp(Color(0.3, 0.4, 0.1), Color(0.2, 0.4, 0.15), data2d.lushness) + Color(colorVariance, colorVariance, colorVariance)

		# Jitter the pos3d
		# Add jiggle to x and z based on noise
		# Add elevation to y based on noise
		var posJittered: Vector3 = Vector3(
			pos3d.x + (worldNoise.get_noise_2dv(Vector2(pos3d.z, pos3d.y)) * 0.5),
			pos3d.y + data2d.elevation,
			pos3d.z + (worldNoise.get_noise_2dv(Vector2(pos3d.x, pos3d.y)) * 0.5)
		)

		return {
			"color": color,
			"material": material,
			"posJittered": posJittered,
		}

# Define the materials
var voxelMaterials: Dictionary = {}
var boxMeshes: Dictionary = {}
var dataGenerator: DataGenerator = DataGenerator.new()
func _ready() -> void:
	# Create the box meshes for each voxel size
	var cVoxelSize: float = chunkSize
	while cVoxelSize > smallestVoxelSize:
		cVoxelSize /= 2
		if cVoxelSize <= largestVoxelSize:
			boxMeshes[cVoxelSize] = BoxMesh.new()
			boxMeshes[cVoxelSize].size = Vector3(cVoxelSize, cVoxelSize, cVoxelSize)

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
	var dataGen: DataGenerator

	var pos: Vector3 = Vector3(0, 0, 0)  # Chunks position
	var multiMeshes: Dictionary = {}  # Store the cubes at each division level
	var chunksVoxelSize: float = largestVoxelSize  # Chunks current subdivision level

	# Hold back subdivisions until you get closer, or to prevent lag
	var progressSubdivisions: Array = []
	var heldSubdivisons: Array = []

	# Create a chunk at a position
	func _init(initPos: Vector3, dataG: DataGenerator) -> void:
		pos = initPos
		dataGen = dataG
	
	# Create the meshes for the chunk
	func initMeshes() -> void:
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
					multiMesh.mesh = get_parent().boxMeshes[cVoxelSize]
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

	func rerenderMultiMeshes() -> void:
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

	func renderVoxel(pos2d: Vector2, pos3d: Vector3, data2d: Dictionary, size: float) -> void:
		var dataColor: Dictionary = dataGen.get_data_color(pos2d, pos3d, data2d, size)
		# Add mesh to multi mesh
		multiMeshes[size][dataColor.material][1].append([dataColor.posJittered, dataColor.color])

		# Add collision shape
		# if size >= 0.5:
		# 	# Create a new BoxMesh
		# 	var box = BoxMesh.new()
		# 	box.size = Vector3(size, size, size)
		# 	var shape: CollisionShape3D = CollisionShape3D.new()
		# 	shape.shape = box
		# 	add_child(shape)

	# Subdivide a voxel into 8 smaller voxels, potentially subdivide those further
	func subdivideVoxel(pos3d: Vector3, voxelSize: float) -> void:
		var hVoxelSize = voxelSize / 2
		# If voxel is too small, render it
		if voxelSize <= smallestVoxelSize:
			var pos2d: Vector2 = Vector2(pos3d.x, pos3d.z)
			var data2d: Dictionary = dataGen.get_data_2d(pos2d)
			var inside3d: bool = dataGen.get_data_3d(data2d, pos3d)
			# If outside the room, render
			if not inside3d:
				renderVoxel(pos2d, pos3d, data2d, voxelSize)
			return

		if voxelSize <= largestVoxelSize:
			# Calculate how much of the voxel is air
			var nAirVoxels: int = 0
			# Smaller voxels have higher threshold for air, so less small voxels made
			var maxAirVoxels: int = 4 if voxelSize == 0.5 else 2 if voxelSize == 1 else 0

			# Fully divide magic lines
			if pos3d.y > -2:
				var noiseMagic: float = dataGen.worldNoise.get_noise_3dv(pos3d * 2)
				if abs(noiseMagic) < 0.05:
					maxAirVoxels = 0
			# Fully divide grass
			var pos2d3: Vector2 = Vector2(pos3d.x, pos3d.z)
			var data2d3: Dictionary = dataGen.get_data_2d(pos2d3)
			if pos3d.y < (data2d3.roomFloor - 4) * 4 - 2:
				var noiseOffset: float = dataGen.worldNoise.get_noise_2dv(pos2d3 * 20) * 0.02
				if data2d3.humidity > 0.5 + noiseOffset:
					maxAirVoxels = 0
			
			for x in [pos3d.x - hVoxelSize, pos3d.x + hVoxelSize]:
				for z in [pos3d.z - hVoxelSize, pos3d.z + hVoxelSize]:
					var data2d: Dictionary = dataGen.get_data_2d(Vector2(x, z))
					for y in [pos3d.y - hVoxelSize, pos3d.y + hVoxelSize]:
						var inside3d: bool = dataGen.get_data_3d(data2d, Vector3(x, y, z))
						if inside3d:
							nAirVoxels += 1
			# If air voxels in threshold range, render it
			if nAirVoxels <= maxAirVoxels:
				var pos2d: Vector2 = Vector2(pos3d.x, pos3d.z)
				var data2d: Dictionary = dataGen.get_data_2d(pos2d)
				renderVoxel(pos2d, pos3d, data2d, voxelSize)
				return
			# If fully air, skip
			if nAirVoxels == 8:
				return
		# Otherwise, subdivide it into 8 smaller voxels
		for x in [-hVoxelSize, hVoxelSize]:
			for z in [-hVoxelSize, hVoxelSize]:
				for y in [-hVoxelSize, hVoxelSize]:
					var pos2: Vector3 = pos3d + Vector3(x, y, z) * 0.5

					# Hold back some subdivisions to render later
					if hVoxelSize < chunksVoxelSize:
						heldSubdivisons.append([pos2, hVoxelSize])
					else:
						progressSubdivisions.append([pos2, hVoxelSize])

	# Progress on subdivisions
	func progress(startTime: float) -> int:
		var subdivisionRate: int = 0
		var newProgress: Array = []
		for subdivision in progressSubdivisions:
			# Try to maintain a good framerate
			if Time.get_ticks_msec() - startTime > msBudget:
				newProgress.append(subdivision)
			else:
				subdivideVoxel(subdivision[0], subdivision[1])
				subdivisionRate += 1
		progressSubdivisions = newProgress
		rerenderMultiMeshes()
		return subdivisionRate

	# Release subdivisions
	func releaseSubdivisions(newVoxelSize: float) -> void:
		chunksVoxelSize = newVoxelSize
		progressSubdivisions += heldSubdivisons
		heldSubdivisons = []


var chunks: Dictionary = {}
var chunkToProgress: Array = []
var subdivisionRates = []

func sortAscending(a: Array, b: Array) -> bool:
	if a[0] < b[0]:
		return true
	return false

func getChunksToProgress(camera: Node3D, cameraPos: Vector3, cameraChunkPos: Vector3) -> void:
	chunkToProgress = []

	# Loop through chunks in a spiral pattern
	var hRD: float = float(renderDistance) / 2
	var x: float = 0
	var z: float = 0
	var dx: float = 0
	var dz: float = -1
	for i in range(renderDistance**2):
		if (-hRD <= x and x <= hRD) and (-hRD <= z and z <= hRD):
			# Get chunk position
			for y in [0, 1]:
				# Get chunks distance for quality level
				var chunkDistance: float = Vector3(x, y, z).length()
				# Ignore chunks in a radius outside the render distance
				if chunkDistance > float(renderDistance) / 2:
					continue

				var renderChunkPos: Vector3 = Vector3(cameraChunkPos.x + x * chunkSize, y * chunkSize, cameraChunkPos.z + z * chunkSize)

				var chunk: Chunk = chunks.get(renderChunkPos)
				if chunk == null:
					chunk = Chunk.new(renderChunkPos, dataGenerator)
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
	chunkToProgress.sort_custom(sortAscending)
	# Remove all but the last 20 elements
	if chunkToProgress.size() > 20:
		chunkToProgress.resize(20)
	# Reverse the array so the highest priority is last
	chunkToProgress.reverse()

var frameNumber: int = 0
func _process(_delta: float) -> void:
	# Get time to calculate ms budget
	var startTime: float = Time.get_ticks_msec()
	frameNumber += 1

	# Find chunks near the camera that need to be created
	var camera: Node3D = get_parent().get_node("Camera3D")
	var cameraPos: Vector3 = camera.global_transform.origin

	var cameraChunkPos: Vector3 = Vector3(
		floor(cameraPos.x / chunkSize) * chunkSize,
		floor(cameraPos.y / chunkSize) * chunkSize,
		floor(cameraPos.z / chunkSize) * chunkSize
	)

	var subdivisionRate: int = 0

	# Progress on priority chunk
	if chunkToProgress.size() != 0:
		for i in range(20):
			var chunk: Array = chunkToProgress.pop_back()
			subdivisionRate += chunk[1].progress(startTime)
			# Try to maintain a good framerate
			if Time.get_ticks_msec() - startTime > msBudget:
				break
			if chunkToProgress.size() == 0:
				# Get new chunks to progress
				getChunksToProgress(camera, cameraPos, cameraChunkPos)
				break
	else:
		# Get new chunks to progress
		getChunksToProgress(camera, cameraPos, cameraChunkPos)
	
	# Add subdivision rate to array
	subdivisionRates.append(subdivisionRate)
	# Average subdivision rate over the last 20 frames
	var avgSubdivisionRate: float = 0
	if subdivisionRates.size() > 20:
		for i in range(20):
			avgSubdivisionRate += subdivisionRates[len(subdivisionRates) - 1 - i]
		avgSubdivisionRate /= 20

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
	if frameNumber % 20 == 0:
		var message: Array[String] = []
		message.append("FPS: " + str(Engine.get_frames_per_second()) + ' ' + str(Time.get_ticks_msec() / 1000.0))
		message.append("Total voxels: " + str(totalVoxels))
		# message.append("Total meshes: " + str(totalMeshes))
		# message.append("Total chunks: " + str(chunks.size()))
		message.append("Subdivision rate: " + str(avgSubdivisionRate))
		# 2d Data
		var data2d: Dictionary = dataGenerator.get_data_2d(Vector2(cameraPos.x, cameraPos.z))
		for key in data2d:
			message.append(key + ": " + str(data2d[key]))
		print('\n'.join(message))