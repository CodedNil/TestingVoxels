extends StaticBody3D

const chunkSize: float = 8.0
const largestVoxelSize: float = 4.0
const smallestVoxelSize: float = 0.25

const roomSpacing: float = 150

const renderDistance: int = 32
const yLevels: Array[int] = [0, 1, -1, 2, -2, 3, -3, 4, 5, 6, 7, 8]

const msBudget: float = 8  # Max time to spend on subdivision per update frame

# Get number of quality levels, based on the largest and smallest voxel size
const nQualityLevels: int = int(log(largestVoxelSize / smallestVoxelSize) / log(2))


# Create noise generator class that can be initialised then have functions within
class DataGenerator:
	var worldNoise: FastNoiseLite = FastNoiseLite.new()

	func _init() -> void:
		worldNoise.frequency = 0.03
		worldNoise.seed = 4321

	# Get a noise value clamped from 0 to 1, but the noise is scaled up to clamp extreme values
	func getWorldsNoise(offset: float, pos2d: Vector2, scale: float) -> float:
		return clamp(
			(
				(1 + worldNoise.get_noise_3d(offset * 1000, pos2d.x * scale, pos2d.y * scale) * 1.4)
				* 0.5
			),
			0,
			1
		)

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
		var temperature: float = getWorldsNoise(1, pos2d, 0.025)
		# Humidity scale, between 0 dry and 1 wet
		var humidity: float = getWorldsNoise(2, pos2d, 0.025)
		# Lushness scale, between 0 barren and 1 lush
		var lushness: float = getWorldsNoise(3, pos2d, 0.1)
		# Development scale, between 0 undeveloped and 1 developed
		var development: float = getWorldsNoise(4, pos2d, 0.1)

		# Rock types for colour, iron is red, calcium is white, graphite is black, apatite is blue
		var calcium: float = getWorldsNoise(5, pos2d, 0.1)
		var graphite: float = getWorldsNoise(6, pos2d, 0.1)
		var iron: float = getWorldsNoise(7, pos2d, 0.1)
		var rockColor: Color = Color(
			calcium * 0.8 - graphite * 0.5 + iron * 0.3,
			calcium * 0.8 - graphite * 0.5 + iron * 0.05,
			calcium * 0.8 - graphite * 0.5
		)

		# Get magic type in zone
		var magicChances: Dictionary = {
			"fire": temperature,
			"water": humidity,
			"air": smoothness,
			"earth": 1 - smoothstep(-10, 10, elevation),
		}
		var magicType: String = "fire"
		for magic in magicChances:
			if magicChances[magic] > magicChances[magicType]:
				magicType = magic

		# Get position offset by noise, so it is not on a perfect grid
		var horizontalOffset = Vector2(
			worldNoise.get_noise_1d(pos2d.y / 4) * (roomSpacing / 3),
			worldNoise.get_noise_1d(pos2d.x / 4) * (roomSpacing / 3)
		)

		# Get data for the room
		# Get 2d room center position, pos2d snapped to nearest room spacing point
		var roomPosition: Vector2 = Vector2(
			round(pos2d.x / roomSpacing) * roomSpacing, round(pos2d.y / roomSpacing) * roomSpacing
		)
		# Get room noise seed, based on room position
		var roomSeed: float = roomPosition.x + roomPosition.y * 123
		roomPosition += horizontalOffset
		# Get angle from center with x and z, from -pi to pi
		var roomAngle: float = pos2d.angle_to_point(roomPosition)
		# Get 2d distance from center with x and z
		var roomDist: float = pos2d.distance_to(roomPosition)

		# Calculate room size, based on noise from the angle
		var roomBaseSize: float = (
			lerp(20, 25, smoothness) + worldNoise.get_noise_1d(roomSeed) * lerp(15, 2, smoothness)
		) + getWorldsNoise(8, pos2d * lerp(20, 4, smoothness), 0.1) * 40
		var roomSize0: float = (
			roomBaseSize + worldNoise.get_noise_2d(roomSeed, -PI) * roomBaseSize / 3 * smoothness
		)
		var roomSize: float = (
			roomBaseSize + (worldNoise.get_noise_2d(roomSeed, roomAngle) * roomBaseSize / 3 * smoothness)
		)
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

		# Higher numbers reduce the height exponentially
		var roomFloor: float = 8.0 - getWorldsNoise(11, pos2d, 0.1) * 4
		var roomCeiling: float = 2.0 + getWorldsNoise(12, pos2d, 0.1) * 3

		# Get floor material
		var floorMaterial: String = "stone"
		var floorVariance: float = worldNoise.get_noise_2dv(pos2d * 2)
		var floorVariance2: float = 0.5 + worldNoise.get_noise_2dv(pos2d * 5) * 0.5
		var floorVariance3: float = 0.5 + worldNoise.get_noise_2dv(pos2d * 2 + Vector2(500, 500)) * 0.5
		# Slight offset on the noise to make it look more natural
		var noiseOffset: float = worldNoise.get_noise_2dv(pos2d * 4) * 0.02
		# Use sand color if temperature is high and humidity low
		if temperature > 0.6 + noiseOffset and humidity < 0.4 + noiseOffset:
			floorMaterial = "sand"
		# Use moss color if humidity high
		if humidity > 0.5 + noiseOffset and floorVariance > 0.3 + noiseOffset:
			floorMaterial = "moss"
			roomFloor += 1
			roomCeiling += 10 * ((floorVariance - 0.3 - noiseOffset) / 0.7)
		# Use dirt color around moss
		elif humidity > 0.5 + noiseOffset and (floorVariance - floorVariance2 * 0.5 > 0.05 + noiseOffset or floorVariance2 + noiseOffset < 0.3):
			floorMaterial = "dirt"

		var data2d: Dictionary = {
			"elevation": elevation,
			"smoothness": smoothness,
			"temperature": temperature,
			"humidity": humidity,
			"lushness": lushness,
			"development": development,
			"rockColor": rockColor,
			"magicType": magicType,
			"roomFloor": roomFloor,
			"roomCeiling": roomCeiling,
			"roomPosition": roomPosition,
			"roomDist": roomDist,
			"roomSize": roomSizeLerp,
			"corridorWidth": corridorWidth,
			"corridorDist": corridorDist,
			"floorMaterial": floorMaterial,
			"floorVariance": floorVariance,
			"floorVariance2": floorVariance2,
			"floorVariance3": floorVariance3,
		}
		cachedData2d[pos2d] = data2d
		return data2d

	func get_data_3d(data2d: Dictionary, pos3d: Vector3) -> bool:
		# Check if data is cached
		if pos3d in cachedData3d:
			return cachedData3d[pos3d]

		var roomHeightSmooth: float = data2d.roomFloor if pos3d.y < 0 else data2d.roomCeiling
		var roomDist3d: float = (
			Vector3(
				pos3d.x - data2d.roomPosition.x,
				pos3d.y * roomHeightSmooth,
				pos3d.z - data2d.roomPosition.y
			)
			.length()
		)
		var roomInside3d: bool = roomDist3d < data2d.roomSize

		var corridorDist3d: float = (
			Vector2(data2d.corridorDist, pos3d.y * roomHeightSmooth / 2.0).length()
		)
		var corridorInside3d: bool = corridorDist3d < data2d.corridorWidth

		var inside3d: bool = roomInside3d or corridorInside3d
		cachedData3d[pos3d] = inside3d
		return inside3d

	func get_data_color(
		pos2d: Vector2, pos3d: Vector3, data2d: Dictionary, size: float
	) -> Dictionary:
		# Color from dark to light gray as elevation increases
		var shade: float = pos3d.y / 50
		var color: Color = data2d.rockColor + Color(shade, shade, shade)
		var material: String = "standard"

		# Give the color horizontal lines from noise to make it look more natural
		var noiseShade: float = (
			(0.5 + worldNoise.get_noise_1d(pos3d.y * 20 + pos3d.x * 0.01 + pos3d.z + 0.01) / 2)
			* 0.2
		)
		color += Color(noiseShade, noiseShade, noiseShade)
		# Add brown colors based on 2d noise
		var noiseColor: float = 0.5 + worldNoise.get_noise_2dv(pos2d * 0.1) / 2
		color += Color(noiseColor, noiseColor * 0.5, 0) * 0.1
		# Add dark stone patches
		if data2d.floorVariance3 < 0.5:
			color = lerp(color, color * 0.5, smoothstep(0.5, 0.3, data2d.floorVariance3))

		# Add magic lines based on 3d noise
		# if pos3d.y > -2 and size <= 1:
		# 	var noiseMagic: float = worldNoise.get_noise_3dv(pos3d * 2)
		# 	var magicAmount: float = smoothstep(-2, 10, pos3d.y)
		# 	if abs(noiseMagic) < 0.05 * magicAmount:
		# 		var magicColor: Color = Color(0, 0, 0)
		# 		if data2d.magicType == "fire":
		# 			magicColor = Color(1, 0, 0)
		# 		elif data2d.magicType == "water":
		# 			magicColor = Color(0, 0, 1)
		# 		elif data2d.magicType == "air":
		# 			magicColor = Color(1, 1, 1)
		# 		elif data2d.magicType == "earth":
		# 			magicColor = Color(0.5, 0.25, 0.05)
		# 		# magicColor *= 1 - abs(noiseMagic) * 10
		# 		color = magicColor#color * 0.1 + magicColor
		# 		material = "emissive_" + data2d.magicType

		# Add color on floors
		if pos3d.y < (data2d.roomFloor - 4) * 4 - 2 and material == "standard":
			var colorVariance: float = data2d.floorVariance * 0.15
			if data2d.floorMaterial == "sand":
				color = Color(1 + colorVariance, 0.9 + colorVariance, 0.6 + colorVariance)
			elif data2d.floorMaterial == "moss":
				color = (
					lerp(Color(0.3, 0.4, 0.1), Color(0.2, 0.4, 0.15), data2d.lushness)
					+ Color(colorVariance, colorVariance, colorVariance)
				)
			elif data2d.floorMaterial == "dirt":
				color = Color(0.6 + colorVariance, 0.3 + colorVariance, 0.05 + colorVariance)
		if data2d.floorMaterial == "moss":
			var colorVariance: float = data2d.floorVariance * 0.15
			color = (
				lerp(Color(0.3, 0.4, 0.1), Color(0.2, 0.4, 0.15), data2d.lushness)
				+ Color(colorVariance, colorVariance, colorVariance)
			)
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

var voxelMaterials: Dictionary = {}
var boxMeshes: Dictionary = {}
var boxShapes: Dictionary = {}
var dataGenerator: DataGenerator = DataGenerator.new()


# Chunk class
class Chunk:
	extends Node3D
	var dataGen: DataGenerator

	var pos: Vector3 = Vector3(0, 0, 0)  # Chunks position
	var multiMeshes: Dictionary = {}  # Store the cubes at each division level
	var chunksVoxelSize: float = largestVoxelSize  # Chunks current subdivision level

	var voxelsCount: int = 0  # Number of voxels in the chunk
	var filled: bool = false  # Is the chunk filled with voxels
	var empty: bool = true  # Is the chunk empty of voxels

	# Hold back subdivisions until you get closer, or to prevent lag
	var progressSubdivisions: Array = []
	var heldSubdivisons: Array = []

	# Create a chunk at a position
	func _init(initPos: Vector3, dataG: DataGenerator) -> void:
		pos = initPos
		dataGen = dataG
		# Create the first subdivision
		subdivideVoxel(pos, chunkSize)
		rerenderMultiMeshes()

	func postInit() -> void:
		if heldSubdivisons.size() > 0:
			empty = false
		var firstMeshCount = 0
		for size in multiMeshes:
			for material in multiMeshes[size]:
				if size == largestVoxelSize:
					firstMeshCount += multiMeshes[size][material][1].size()
		filled = firstMeshCount == 8

	# Clean for cache use
	func clean() -> void:
		for size in multiMeshes:
			for material in multiMeshes[size]:
				var mesh = multiMeshes[size][material][0]
				var meshArray = multiMeshes[size][material][1]
				mesh.instance_count = 0
				meshArray.clear()
		chunksVoxelSize = largestVoxelSize
		progressSubdivisions.clear()
		heldSubdivisons.clear()

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

		# Create multimesh if needed
		if not size in multiMeshes:
			multiMeshes[size] = {}
		if not dataColor.material in multiMeshes[size]:
			var multiMesh: MultiMesh = MultiMesh.new()
			multiMesh.transform_format = MultiMesh.TRANSFORM_3D
			multiMesh.use_colors = true
			multiMesh.use_custom_data = false
			multiMesh.instance_count = 0
			multiMesh.mesh = get_parent().boxMeshes[size]
			var meshInstance: MultiMeshInstance3D = MultiMeshInstance3D.new()
			meshInstance.multimesh = multiMesh
			# Add material
			meshInstance.material_override = get_parent().voxelMaterials[dataColor.material]
			# Add to scene
			add_child(meshInstance)
			# Add to array
			multiMeshes[size][dataColor.material] = [multiMesh, []]

		# Add mesh to multi mesh
		multiMeshes[size][dataColor.material][1].append([dataColor.posJittered, dataColor.color])

		# Add collision shape
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.shape = get_parent().boxShapes[size]
		shape.global_transform = Transform3D(Basis(), dataColor.posJittered)
		get_parent().add_child(shape)

		voxelsCount += 1

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

			if voxelSize <= 0.5:
				# Fully divide magic lines
				# if pos3d.y > -2:
				# 	var noiseMagic: float = dataGen.worldNoise.get_noise_3dv(pos3d * 2)
				# 	var magicAmount: float = smoothstep(-2, 10, pos3d.y)
				# 	if abs(noiseMagic) < 0.05 * magicAmount:
				# 		maxAirVoxels = 3 if voxelSize == 0.5 else 1 if voxelSize == 1 else 0
				# Fully divide grass
				var pos2d3: Vector2 = Vector2(pos3d.x, pos3d.z)
				var data2d3: Dictionary = dataGen.get_data_2d(pos2d3)
				if data2d3.floorMaterial == "moss":
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
			if startTime != 0 and Time.get_ticks_msec() - startTime > msBudget:
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
var chunksCached: Dictionary = {}
var subdivisionRates = []

var frameNumber: int = 0


func _ready() -> void:
	# Create the box meshes for each voxel size
	var cVoxelSize: float = chunkSize
	while cVoxelSize > smallestVoxelSize:
		cVoxelSize /= 2
		if cVoxelSize <= largestVoxelSize:
			boxMeshes[cVoxelSize] = BoxMesh.new()
			boxMeshes[cVoxelSize].size = Vector3(cVoxelSize, cVoxelSize, cVoxelSize)
			boxShapes[cVoxelSize] = BoxShape3D.new()
			boxShapes[cVoxelSize].extents = Vector3(cVoxelSize, cVoxelSize, cVoxelSize) / 2

	# Define the materials
	voxelMaterials["standard"] = preload("res://materials/voxel_standard.tres")

	var magicColors: Dictionary = {
		"fire": Color(0.7, 0.2, 0.2),
		"water": Color(0.2, 0.2, 0.7),
		"air": Color(0.7, 0.7, 0.7),
		"earth": Color(0.5, 0.25, 0.05),
	}
	for magic in magicColors:
		var magicMaterial: StandardMaterial3D = StandardMaterial3D.new()
		magicMaterial.vertex_color_use_as_albedo = true
		magicMaterial.emission_enabled = true
		magicMaterial.emission = magicColors[magic]
		magicMaterial.emission_energy_multiplier = 0.2
		magicMaterial.rim_enabled = true
		voxelMaterials["emissive_" + magic] = magicMaterial


func _process(_delta: float) -> void:
	# Get time to calculate ms budget
	var startTime: float = Time.get_ticks_msec()
	frameNumber += 1

	# Find chunks near the camera that need to be created
	var camera: Node3D = get_parent().get_node("CharacterBody3D")
	var cameraPos: Vector3 = camera.global_transform.origin
	var cameraDir: Vector3 = camera.global_transform.basis.z
	# Temporary fake camera pos
	# cameraPos = Vector3(0, 0, 0)
	# cameraDir = Vector3(0, 0, 1)

	# If camera is looking down, pause
	# var paused: bool = camera.get_node("CameraRotator").rotation.x < -1

	var subdivisionRate: int = 0

	# Previous chunk searching Chunks: 10404 Meshes: 27774 Voxels: 248065

	# Progress on chunks
	var chunksViewed: Array[Vector2] = []
	var rotateAngles: float = 32
	# Get rotate per run and jitter
	var rotatePerRun: float = 360 / rotateAngles
	var jitter: float = sin(Time.get_ticks_msec() / 500.0) * rotatePerRun
	# Keep track of chunks to progress by voxel size, so we can progress in order of quality
	var chunksToProgress: Dictionary = {}
	for qLevel in range(nQualityLevels + 1):
		var voxelSize: float = largestVoxelSize / pow(2, qLevel)
		chunksToProgress[voxelSize] = []

	# Loop through chunks in rotated lines from center
	for angle in range(rotateAngles / 2):
		# 0 to 1 for the angle of rotation
		var angleQuality: float = angle / rotateAngles * 2
		# Start rotation from 0, then -angle, then angle, then -angle * 2, then angle * 2, etc
		var flip: int = 1 if angle % 2 == 0 else -1
		var dir: Vector3 = cameraDir.rotated(
			Vector3(0, 1, 0), deg_to_rad(180 + angle * flip * rotatePerRun + jitter)
		)
		for i in range(renderDistance):
			var pos: Vector3 = cameraPos + dir * i * chunkSize

			var renderChunkPos2d: Vector2 = Vector2(int(pos.x / chunkSize), int(pos.z / chunkSize)) * chunkSize
			# If the chunk is already in the list, skip it
			if renderChunkPos2d in chunksViewed:
				continue
			chunksViewed.append(renderChunkPos2d)

			# Get if entire y range is empty space, skip if is
			var emptyY: int = 0
			for y in yLevels:
				# Get the rounded snapped chunk position
				var renderChunkPos: Vector3 = (
					Vector3(int(pos.x / chunkSize), y, int(pos.z / chunkSize)) * chunkSize
				)
				# Find if chunk exists
				var chunk: Chunk = chunks.get(renderChunkPos)
				if chunk == null:
					# Create new chunk or retrieve from cache
					if chunksCached.size() > 0:
						var key = chunksCached.keys()[0]
						chunk = chunksCached[key]
						chunksCached.erase(key)
						chunk.clean()
						chunk._init(renderChunkPos, dataGenerator)
					else:
						chunk = Chunk.new(renderChunkPos, dataGenerator)
						add_child(chunk)
					chunks[renderChunkPos] = chunk
					subdivisionRate += chunk.progress(0)
					chunk.postInit()
				else:
					if chunk.progressSubdivisions.size() != 0:
						chunksToProgress[chunk.chunksVoxelSize].append(chunk)
					elif (
						chunk.heldSubdivisons.size() != 0
						and chunk.progressSubdivisions.size() == 0
					):
						# Get the distance from the camera
						var chunkDistance: float = renderChunkPos2d.distance_to(Vector2(cameraPos.x, cameraPos.z)) / chunkSize
						# Get the chunks minimum voxel size, based on how close it is to the camera, halved from max each time
						var subdivisionLevel: int = clamp(
							round(
								nQualityLevels - chunkDistance * lerp(0.7 * smallestVoxelSize, 1.2 * smallestVoxelSize, angleQuality) + 1.0
							),
							0,
							nQualityLevels
						)
						var newVoxelSize: float = largestVoxelSize / pow(2, subdivisionLevel)

						# Release subdivisions if the voxel size is too big
						if chunk.chunksVoxelSize > newVoxelSize:
							chunk.releaseSubdivisions(chunk.chunksVoxelSize / 2)

				# If chunk is filled, can skip it
				if chunk.filled:
					emptyY += 1
			if emptyY == len(yLevels):
				break
			# If we have gone over the time budget, break
			if Time.get_ticks_msec() - startTime > msBudget:
				break
		if Time.get_ticks_msec() - startTime > msBudget:
			break

	# Progress on chunks
	for voxelSize in chunksToProgress:
		for chunk in chunksToProgress[voxelSize]:
			subdivisionRate += chunk.progress(startTime)
			if Time.get_ticks_msec() - startTime > msBudget:
				break
		if Time.get_ticks_msec() - startTime > msBudget:
			break

	# Add subdivision rate to array
	subdivisionRates.append(subdivisionRate)

	# Remove chunks that are too far away
	var chunksToRemove: Array[Vector3] = []
	for chunkPos in chunks:
		if chunkPos.distance_to(cameraPos) > renderDistance * 1.2 * chunkSize:
			chunksToRemove.append(chunkPos)
	# Remove max x chunks per frame
	for chunkPos in chunksToRemove:
		chunksCached[chunkPos] = chunks[chunkPos]
		chunks.erase(chunkPos)

	# Print stats
	if frameNumber % 10 == 0:
		# Average subdivision rate over the last 20 frames
		var avgSubdivisionRate: float = 0
		if subdivisionRates.size() > 20:
			for i in range(20):
				avgSubdivisionRate += subdivisionRates[len(subdivisionRates) - 1 - i]
			avgSubdivisionRate /= 20
		
		var totalVoxels: int = 0
		var totalMeshes: int = 0
		for chunkPos in chunks:
			totalVoxels += chunks[chunkPos].voxelsCount
			totalMeshes += chunks[chunkPos].multiMeshes.size() * voxelMaterials.size()
		
		var message: Array[String] = []
		message.append(
			(
				"FPS: "
				+ str(Engine.get_frames_per_second())
				+ " "
				+ str(Time.get_ticks_msec() / 1000.0)
			)
		)
		message.append(
			(
				"Chunks: "
				+ str(chunks.size())
				+ " Meshes: "
				+ str(totalMeshes)
				+ " Voxels: "
				+ str(totalVoxels)
			)
		)
		message.append("Subdivision rate: " + str(avgSubdivisionRate))
		# 2d Data
		# var data2d: Dictionary = dataGenerator.get_data_2d(Vector2(int(cameraPos.x), int(cameraPos.z)))
		# for key in data2d:
		# 	message.append(key + ": " + str(data2d[key]))
		print("\n".join(message))
