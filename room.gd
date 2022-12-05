extends Node3D


var extents = Vector3(10, 1, 10)
var voxelSize = 0.25

func _ready():
	var noiseHeight = FastNoiseLite.new()
	noiseHeight.set_noise_type(FastNoiseLite.TYPE_SIMPLEX)
	noiseHeight.set_frequency(0.03)
	noiseHeight.seed = 1234
	
	# Create boxes within extents
	for x in range(-extents.x / voxelSize / 2, extents.x / voxelSize / 2):
		for y in range(-extents.y / voxelSize / 2, extents.y / voxelSize / 2):
			for z in range(-extents.z / voxelSize / 2, extents.z / voxelSize / 2):
				var pos = Vector3(x * voxelSize, y * voxelSize, z * voxelSize)

				# Set y to simplex noise
				pos.y += noiseHeight.get_noise_2d(pos.x, pos.z) * 2

				# Create a new BoxMesh
				var box = BoxMesh.new()
				box.size = Vector3(voxelSize, voxelSize, voxelSize)
				# Assign a random color to the box
				var color = Color(randf(), randf(), randf())
				# Create a new MeshInstance
				var mesh = MeshInstance3D.new()
				mesh.mesh = box
				mesh.material_override = StandardMaterial3D.new()
				mesh.material_override.albedo_color = color
				# Add mesh as a child of this node
				add_child(mesh)
				# Position the mesh
				mesh.transform.origin = pos
