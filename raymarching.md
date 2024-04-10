# Raymarching
Some people use raymarching to create cool effects in VRChat. This page does not aim to teach raymarching, but rather sum up the specific steps requried to get raymarched shaders running nicely in game.

## Learning raymarching
To actually learn raymarching, I suggest these links:
- http://jamie-wong.com/2016/07/15/ray-marching-signed-distance-functions/
- https://iquilezles.org/www/articles/distfunctions/distfunctions.htm
- https://www.youtube.com/watch?v=khblXafu7iA
- https://www.youtube.com/watch?v=PGtv-dBi2wE
- https://www.shadertoy.com/view/XllGW4
- https://www.shadertoy.com/

An well commented example of small raymarcher I've written [is available here](https://github.com/pema99/shader-knowledge/blob/main/attachments/RaymarchingExample.shader). It shows marching both in world and object space, as well as how to write depth values.

## Setting up the camera
To make our raymarched shader look 3D in Unity (and in game), we need to calculate the ray origin and direction for each pixel based on the main camera position.

Add a property for the ray origin and vertex position to your fragment input struct:
```glsl
struct v2f
{
    float3 ray_origin : TEXCOORD1;
    float3 vert_position : TEXCOORD2;
};
```

Next, in the vertex shader, calculate these fields. If you want to do raymarching in world space, do the following:
```glsl
v2f vert (appdata v)
{
    v2f o;
    ... initialize other fields

    o.ray_origin = _WorldSpaceCameraPos;
    o.vert_position = mul(unity_ObjectToWorld, v.vertex);

    return o;
}
```
For marching in object space instead, do the following:
```glsl
v2f vert (appdata v)
{
    v2f o;
    ... initialize other fields

    o.ray_origin = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1));
    o.vert_position = v.vertex;

    return o;
}
```

Now, in the fragment shader, you can calculate the ray origin and direction for each fragment as such:

```glsl
float4 frag (v2f i) : SV_Target
{
    float3 ray_origin = i.ray_origin;
    float3 ray_direction = normalize(i.vert_position - i.ray_origin);
    
    ... do the raymarching
}
```

## Handling ray origin outside of the object being shaded
Let's say your raymarched shader is on a cube. If the player is outside of this cube, and you just set the ray origin to the camera position, it will look very jarring. There are many ways to deal with this, I do the following:

Set culling off:
```glsl
SubShader
{
    Cull Off
    ...
}
```

Extend the fragment shader to accept a value using the `VFACE` semantic:
```glsl
float4 frag (v2f i, float facing : VFACE) : SV_Target
{
    ...
}
```

Now, right after calculating the ray origin, do the following:
```glsl
float4 frag (v2f i, float facing : VFACE) : SV_Target
{
    float ray_origin = ...;

    if (facing > 0) // if front face, move ray origin to vertex pos
        ray_origin = i.vert_position;
}
```

## Writing depth
To have your raymarched shader properly interact with other renderers, you need to write depth from the fragment shader. Add a new `out` variable with the `SV_Depth` semantic:

```glsl
float4 frag (v2f i, out float depth : SV_Depth) : SV_Target
{
    ...
}
```

And in the fragment shader, after calculating the position on the surface that the ray hit, use this to calculate and output depth:

```glsl
// However you calculate hit_position, make sure it is in world space
float3 hit_position = ray_origin + ray_distance * ray_direction;

// Output depth
float4 clip_pos = mul(UNITY_MATRIX_VP, float4(hit_position, 1.0));
depth = clip_pos.z / clip_pos.w;
```

## SV_DepthLessEqual
One issue with writing to the SV_Depth semantic is that disables early Z testing, which might cause performance issues. Another, lesser known semantic exists, which allows you to write depth without disabling early Z testing. The semantic `SV_DepthLessEqual` functions the same as `SV_Depth` but doesn't disable early Z testing as long as the written value is less or equal to the value determined by the rasterizer.

This semantic requires using a more recent shading model - add `#pragma target 5.0` to your shader to enable it.

## Performance considerations
Please remember that raymarching can be very expensive, especially in VR at Index-like resolutions. As a rule of thumb:

- Try to keep iteration steps for the marching loop low. Under 50 is preferrable.
- Always have a maximum distance for march, at which point you just stop marching.
- Try to keep distance functions simple, this is the main way to keep performance under control.
