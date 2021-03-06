# Geometry shaders

Geometry shaders are a cool tool that can be used to create geometry within a shader on the fly. They have many use cases within the limitations of VRChat, for example for making duplicate of an avatar that mirror your movements, for rendering GPU particles, for blitting into camera loop buffers, and much more.

## Writing geometry shaders
Most geometry shaders take a stream of triangles as input and produce a stream of triangles as output. For each triangle received as input, one can create many triangles as output. It doesn't make sense to teach how to write geometry shaders in general, and I instead focus on techniques useful specifically for VRChat. For good tutorials on how to write them, see here:
- https://halisavakis.com/my-take-on-shaders-geometry-shaders/
- https://medium.com/chenjd-xyz/using-the-geometry-shader-in-unity-to-generate-countless-of-grass-on-gpu-4ca6d78b3de6

## Performance rank spoofing
One nice property of geometry in VRChat is that they bypass the performance rating system. Any extra generated geometry will not count towards to total polygon count of the avatar. Use responsibly!

## Degenerate meshes for generating geometry
One useful tool when working with geometry shaders in VRChat are degenerate meshes. In this context, I specifically mean meshes 1 vertex but many triangles. Below is a script to generate them, courtesy of Nave and Neitri:
```csharp
// idea by Nave, original: https://pastebin.com/Q43UPHf4
#if UNITY_EDITOR
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;

public class CreateParticlesMesh : MonoBehaviour
{
	[MenuItem("GameObject/Create Paricles Mesh")]
	static void DoIt()
	{
		int size = 1024; // Change this value to what you want
		var mesh = new Mesh();
		mesh.vertices = new Vector3[] { new Vector3(0, 0, 0) };
		mesh.triangles = new int[size * size * 3];
		mesh.bounds = new Bounds(new Vector3(0, 0, 0), new Vector3(1, 1, 1));
		string path = "Assets/" + size + "x" + size + ".asset";
		AssetDatabase.CreateAsset(mesh, path);
		EditorGUIUtility.PingObject(mesh);
	}
}
#endif
```

Applying a geometry shader to a renderer using such a degenerate mesh allows for easily and cleanly creating a large amount of triangles in a geometry shader.

## SV_PrimitiveID
The `SV_PrimitiveID` semantic can be used to get a unique identifier for each triangle in the geometry shader. This is useful if the geometry you are generating from the geometry shader is not dependent on the input mesh (for example when using a degenerate mesh as above), but you are just trying to generate a large amount geometry with different properties, such as location. You can base these properties off the unique identifer.

```glsl
#pragma target 5.0
#pragma geometry geom
...

[maxvertexcount(12)]
void geom(triangle v2f IN[3],
    inout TriangleStream<g2f> tristream,
    uint triID : SV_PrimitiveID)
{
    ... //use triID in calculations
}
```

## Geometry instancing and limits
To improve performance, and to allow for pushing even more data out of a geometry shader, it is useful to use geometry instancing. This allows multiple executions of the same geometry shader per primitive. It is fairly simple to setup:

Add an `[instance(n)]` attribute to the geometry function where `n` is a number less or equal to 32. Then, add another input the geometry function with the `SV_GSInstanceID` semantic. This input will indicate the index of the current instance. You can use the index together with the `SV_PrimitiveID` semantic to get a unique identifier for each invocation of the shader.

```glsl
#pragma target 5.0
#pragma geometry geom
...

[instance(8)]
[maxvertexcount(12)]
void geom(triangle v2f IN[3],
    inout TriangleStream<g2f> tristream,
    uint instanceID : SV_GSInstanceID)
{
    ...
}
```
This example will essentially invoke the geometry function 8 times instead of only once, passing a different value to the input using the `SV_GSInstanceID` semantic each time. In general, you should prefer geometry instancing over increasing the `maxvertexcount` for best performance.

There are some limits to how much data each invocation of a geometry shader can produce. This can be increased multiplicatively using geometry instancing as shown above. When combined with tesselation, one can push an absurd amount of data out of a geometry shader.

Some more information about this feature can be found on MSDN: https://docs.microsoft.com/en-us/windows/win32/direct3dhlsl/overviews-direct3d-11-hlsl-gs-instance

## Blitting to camera loops (or cameras in general)
One advanced use case for geometry shaders is enabling random writes in a camera loop. For more information on camera loops in general, see the separate [page on them](camera-loops.md). Camera loops have an inherent limitation in that you can only write to the pixel that is currently being shaded. Using a geometry shader, you can get around that limitation, by simply spawning geometry in front of the quad that the camera is capturing for the loop. Spawning a pixel-sized quad with a specific color in front of the camera is functionally equivalent to blitting a pixel with that color to the corresponding location in the RenderTexture.

More generally, geometry shaders can be viewed as a tool for writing to RenderTextures in a flexible way - a loop is not strictly necessary. One thing I have used a geometry shader for in the past was storing the vertex positions of a skinned mesh for use in a different shader. I applied a geometry shader to the skinned mesh which created a grid of small quads, one for each vertex of the mesh, each with a color encoding the corresponding vertex position. A camera then captured this grid of quads to a RenderTexture which I could use elsewhere.

For an example of using a geometry shader to draw data into the clipspace of a camera (directly onto the screen) see [this gist](https://gist.github.com/pema99/8b385ae6cef2736f4dea2fd6d4ead01c). If combined with a subsequent GrabPass, this data can be made globally accessible, since the GrabPass will essentially take a screenshot of the data that is put directly onto the screen.

## Blitting to CRT (Custom Render Texture)
Similar as can be done with cameras, one can use geometry shaders to achieve arbitrary writes in Custom Render Texture shaders. For an example of this, see [cnlohr's flexcrt repo](https://github.com/cnlohr/flexcrt).

## Examples
- [Show vertex positions on screen](https://gist.github.com/pema99/8b385ae6cef2736f4dea2fd6d4ead01c)
- [Standard Geometry Shader](https://github.com/keijiro/StandardGeometryShader)
