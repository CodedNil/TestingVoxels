using Godot;
using System;

public partial class voxel_terrain : StaticBody3D
{
    // Create an instance of FastNoiseLite
    FastNoiseLite noise = new FastNoiseLite();

    public override void GetData2D(float x, float z)
    {
		// World elevation offset for nice gradient slopes, -10 to 10, could have caves going uphill or downhill
		float elevation = noise.GetNoise(x, z) * 10;
    }

    // Called when the node enters the scene tree for the first time.
    public override void _Ready()
    {
        noise.SetSeed(1337);
    }

    // Called every frame. 'delta' is the elapsed time since the previous frame.
    public override void _Process(double delta)
    {
    }
}
