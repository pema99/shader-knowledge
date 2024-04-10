# Tips and tricks
A document for various small tips and tricks I've picked up that don't warrant their own full pages.

### Point light position abuse
Many people use point lights to get the positions of arbitrary objects in shaders. To do this, first set `LightMode` of your shader to a setting that will allow for sampling lights:

```glsl
Tags { "LightMode"="FowardBase" }
...
```

Then, in the shader, you can use this code to get the world space position of the `i`'th point light (`i` can be from 0-3).
```glsl
float3 light_pos = float3(unity_4LightPosX0[i], unity_4LightPosY0[i], unity_4LightPosZ0[i]);
```

To prevent annoyance, most people set the color of their point lights to fully back (0, 0, 0) and use the alpha value to distinguish between point lights. You can get the alpha value of the `i`'th light as so:

```glsl
unity_LightColor[i].a
```

It is important to set the 'Render Mode' of the point light to 'Not Important' to force the light to be a vertex light.

If possible, you should also put the lights 'Culling Mask' to only 'UiMenu' and put whatever you want to interact with the light on that same layer. That way, you don't add passes to everybodies avatar, causing lag. The UiMenu layer, unlike most other layers, is usable even on avatars.

The `unity_4LightPos` arrays will contain positions of vertex lights, but may also contain positions of pixel lights (Render Mode = Important or Auto) if the shader doesn't contain an add pass. To prevent these arrays from being polluted with random pixel lights, you can add an additional pass to the shader with the tag `Tags { "LightMode"="ForwardAdd" }`, which does nothing:
```glsl
... main pass goes above here

Pass
{
    Tags { "LightMode"="ForwardAdd" }
    CGPROGRAM
    #pragma vertex empty
    #pragma fragment empty
    void empty(){}
    ENDCG
}
```

### Exporting textures with GrabPass
Textures from named GrabPasses will be available globally in any shader, ie:

```glsl
GrabPass { "_MyGlobalTexture" }
```

Then any shader can access it by just declaring a field:
```glsl
...
sampler2D _MyGlobalTexture;
...
```
[This is what AudioLink uses to make a data texture available to avatars](https://github.com/llealloo/vrc-udon-audio-link/blob/master/AudioLink/Shaders/AudioTextureExport.shader)

### Checking if a texture exists
You can check for existance (if it has been set) of a texture as such:
```glsl
Texture2D _MyTexture;

bool TextureExists()
{
    int width, height;
    _MyTexture.GetDimensions(width, height);
    return width > 16;
}
```
This is especially useful when accessing globally exported GrabPass textures. Keep in mind the texture must be declared as `Texture2D`, not `sampler2D`.
Thanks to ACIIL for finding this originally.

To make use of this in a surface shader, you should wrap the code in a `SHADER_TARGET_SURFACE_ANALYSIS` guard:
```glsl
#ifndef SHADER_TARGET_SURFACE_ANALYSIS
// call Texture2D.GetDimensions here
#endif
```

### Cheap wireframe abusing MSAA
Courtesy of d4rkpl4y3r.
```glsl
float4 frag (centroid float4 p : SV_POSITION) : SV_Target
{
    return any(frac(p).xy != 0.5);
}
```

### Avoiding draw order issues with transparent shaders
You can add a pass in front of the main pass for a transparent shader which just fills the depth buffer as such:
```glsl
Pass
{
    ZWrite On
    ColorMask 0
}
```
Comparison without and with this pass

![img](images/Misc1.png)

### GLSL modulo operator
Use this instead of HLSL's piece of shit `fmod`. It behaves better on negative numbers.
```glsl
#define glsl_mod(x,y) (((x)-(y)*floor((x)/(y))))
```

### Some tricks with shader properties
You can make an integer slider property using the IntRange attribute such:

```glsl
Properties {
    [IntRange] _MyIntSlider ("My Int Slider", Range(0, 10)) = 0
}
```

Properties can be used to control shader settings such as culling, blend modes, depth buffer writing, etc. Example:

```glsl
Properties
{
    [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 0
    [ToggleUI] _ZWrite ("ZWrite", Float) = 0
}
SubShader
{
    Cull [_Cull]
    ZWrite [_ZWrite]
}
```

**Always** make sure to use the `[ToggleUI]` attribute for checkboxes. Never use `[Toggle]` as it implicitly creates a keyword.

You can also create enum dropdown properties manually as such:
```glsl
Properties {
    [Enum(One,1,SrcAlpha,5)] _Blend2 ("Blend mode subset", Float) = 1
}
```
The values are pairs of (dropdown name, dropdown value).

### Applying default texture to shader
If you open the inspector for a **shader** (not a specific material), you can drag default values for textures on to each texture property. Any material created from the shader will inherit this texture as the default.

![img](image/../images/Misc2.png)

### Functions for detecting VRChat specific scenarios
Note: Some of these are obsolete. Use [VRChat's builtin shader globals](https://creators.vrchat.com/worlds/vrc-graphics/vrchat-shader-globals/) where possible.
Courtesy of ScruffyRuffles and Merlin.
```glsl
bool isVR() {
    #if UNITY_SINGLE_PASS_STEREO
        return true;
    #else
        return false;
    #endif
}

bool isVRHandCamera() {
    return !isVR() && abs(UNITY_MATRIX_V[0].y) > 0.0000005;
}

bool isDesktop() {
    return !isVR() && abs(UNITY_MATRIX_V[0].y) < 0.0000005;
}

bool isVRHandCameraPreview() {
    return isVRHandCamera() && _ScreenParams.y == 720;
}

bool isVRHandCameraPicture() {
    return isVRHandCamera() && _ScreenParams.y == 1080;
}

bool isPanorama() {
    return unity_CameraProjection[1][1] == 1 && _ScreenParams.x == 1075 && _ScreenParams.y == 1025;
}

bool isInMirror()
{
    return unity_CameraProjection[2][0] != 0.f || unity_CameraProjection[2][1] != 0.f;
}
```

```glsl
uniform float _VRChatMirrorMode;
uniform float3 _VRChatMirrorCameraPos;

bool IsVR() {
    #if defined(USING_STEREO_MATRICES)
    return true;
    #else
    return _VRChatMirrorMode == 1;
    #endif
}

bool IsRightEye()
{
    #if defined(USING_STEREO_MATRICES)
    return unity_StereoEyeIndex == 1;
    #else
    return _VRChatMirrorMode == 1 && mul(unity_WorldToCamera, float4(_VRChatMirrorCameraPos, 1)).x < 0;
    #endif
}

bool IsLeftEye() { return !IsRightEye(); }

bool IsDesktop() { return !IsVR(); }
```

### Inline sampler states
Sometimes you want to control the settings used for sampling a texture you don't have access to the importer for, like a texture exported from a GrabPass. In such cases, you can use inline sampler states ([https://docs.unity3d.com/Manual/SL-SamplerStates.html](https://docs.unity3d.com/Manual/SL-SamplerStates.html)). The idea is to include certain keywords in the name of your `SamplerState` declaration:

```glsl
Texture2D _MainTex;
SamplerState my_point_clamp_sampler;
// ...
half4 color = _MainTex.Sample(my_point_clamp_sampler, uv);
```
Notice the name 'my_point_clamp_sampler'. The following case insensitive keywords apply:
| Keyword    | Meaning                                   |
|------------|-------------------------------------------|
| Point      | Point (nearest neighbor) filtering.       |
| Linear     | Bilinear filtering.                       |
| Trilinear  | Trilinear filtering.                      |
| Clamp      | Clamp when reading outside of [0;1]       |
| Repeat     | Repeat when reading outside of [0;1]      |
| Mirror     | Mirror when reading outside of [0;1]      |
| MirrorOnce | Mirror Once when reading outside of [0;1] |
| Compare    | Set up sampler for depth comparison       |

### Update When Offscreen setting for Skinned Mesh Renderer
The "Update When Offscreen" setting on Skinned Mesh Renderers has special behavior in VRChat.

For the local avatar, this setting is forced **on**.

For all remote avatars, this setting is forced **off**.

Both of these behaviors happen regardless of the settings you have chosen. This can cause culling issues when part of a Skinned Mesh Renderer is outside of its minimal bounding box (for example when creating geometry with a geometry shader), and may lead to issues where remote players can see the geometry, but the local player cannot.

Similar to cameras, you can override this behaviour with an animation targeting the setting, for example if you want to have your custom (or even animated) bounds apply locally too.

Thank you Lox for enlightening me with this arcane knowledge.

### Usable default values for shader texture properties
When declaring a texture property in a shader, you can set a default value for it:
```txt
_MainTex ("My Texture", 2D) = "white"{}
```
Most people know of values such as "white" and "black", but there are quite a few other undocumented ones. Here is a list of some values you can use:
```glsl
red
gray
grey
linearGray
linearGrey
grayscaleRamp
greyscaleRamp
bump
blackCube
lightmap
unity_Lightmap
unity_LightmapInd
unity_ShadowMask
unity_DynamicLightmap
unity_DynamicDirectionality
unity_DynamicNormal
unity_DitherMask
_DitherMaskLOD
_DitherMaskLOD2D
unity_RandomRotation16
unity_NHxRoughness
unity_SpecCube0
unity_SpecCube1
unity_ProbeVolumeSH
```
This is useful for scenarios where you want users to be able to set an override for, for example, lightmaps or reflection probes:
```txt
_LightmapOverride ("Lightmap", 2D) = "unity_Lightmap"{}
_ReflectionProbeOverride ("Reflection", CUBE) = "unity_SpecCube0"{}
```

### CBuffer aliasing
Unity only lets you set uniform arrays on a material up to a length of 1023. You can get around this limitation by aliasing arrays using `packoffset` in a cbuffer, like so:
```glsl
cbuffer ProgramBuffer {
    float4 _Program[1023*4] : packoffset(c0);  
    float4 _Program0[1023] : packoffset(c0);
    float4 _Program1[1023] : packoffset(c1023);
    float4 _Program2[1023] : packoffset(c2046);
    float4 _Program3[1023] : packoffset(c3069);
};
```

With this, each of the 4 numbered arrays will overlap with with larger array. By calling `Material.SetVectorArray` 4 times, you can fill the entire array with data, foregoing the limitation, and letting you use the larger array in your shader. You can set each part like so:
```csharp
myMaterial.SetVectorArray("_Program0", arrayPart0);
myMaterial.SetVectorArray("_Program1", arrayPart1);
myMaterial.SetVectorArray("_Program2", arrayPart2);
myMaterial.SetVectorArray("_Program3", arrayPart3);
```

When using this technique, you have to trick the compiler into not compiling out the seemingly unused arrays. You can do this by adding them to a calulation in your shader in a branch that will never be hit:
```glsl
// Hack to prevent unity from deleting aliased cbuffer. Branch will never be hit
if (uv.x < 0) someValuedUsedInFurtherCalculation = _Program0[0] + _Program1[0] + _Program2[0] + _Program3[0]; 
```

The only limitation of this technique is the maximum size allowable for the cbuffer, which is 64kib, so for a float4 array (16 bytes per element), that gives you a max array size of roughly 4096. Keep in mind though, that Unity limits each aliased array to 1023 elements, not 1024!

### Attributes on flow control
You can put various attributes in front of a switch statement, which can improve performance quite a bit depending on the use case. For example, use `forcecase` to force the compiler to generate a jump table:
```glsl
[forcecase] switch (myValue)
{
   ...
}
```
Which for some reason isn't the default.

Some pages showing attributes for switch statements and other flow control:
- https://docs.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-switch
- https://docs.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-if
- https://docs.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-while
- https://docs.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-for

### Easy way to show UV unwrap in clipspace
```glsl
Shader "UVUnwrap"
{
    SubShader
    {
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (float2 uv : TEXCOORD0)
            {
                v2f o;
                o.vertex = float4(float2(1,-1)*(uv*2-1),0,1);
                o.uv = uv;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                return float4(i.uv, 0, 1);
            }
            ENDCG
        }
    }
}
```

Note the `o.vertex = float4(float2(1,-1)*(uv*2-1),0,1);`. Thanks, Lyuma.

### Encoding and decoding data in a GrabPass
In worlds with HDR-enabled, GrabPasses will write to a FP16 render target, making them slightly annoying to encode data in. For this purpose, Merlin wrote some nice functions to store perfect 32 bit uints (or perfect 32 bit floats by first converting) in a half-precision float vector.
```glsl
// Packing/unpacking routines for saving integers to R16G16B16A16_FLOAT textures
// Heavily based off of https://github.com/apitrace/dxsdk/blob/master/Include/d3dx_dxgiformatconvert.inl
// For some reason the last 2 bits get stomped so we'll only allow uint14 for now :(
float uint14ToFloat(uint input)
{
    precise float output = (f16tof32((input & 0x00003fff)));
    return output;
}

uint floatToUint14(precise float input)
{
    uint output = (f32tof16(input)) & 0x00003fff;
    return output;
}

// Encodes a 32 bit uint into 3 half precision floats
float3 uintToHalf3(uint input)
{
    precise float3 output = float3(uint14ToFloat(input), uint14ToFloat(input >> 14), uint14ToFloat((input >> 28) & 0x0000000f));
    return output;
}

uint half3ToUint(precise float3 input)
{
    return floatToUint14(input.x) | (floatToUint14(input.y) << 14) | ((floatToUint14(input.z) & 0x0000000f) << 28);
}
```

### Skipping shader optimization
You can make larger shaders compile much faster by disabling compiler optimizations using a pragma. Add a line like this to your shader:

```glsl
#pragma skip_optimizations d3d11
```

Where `d3d11` is the graphics API you are using. Note that this will make the compiled shader less performant, so is mostly useful when iterating. Never leave this line in shaders intended for production.

### Matrix inversion
A simple function to invert a matrix, Thanks Lox

```glsl
float4x4 inverse(float4x4 mat)
{
	float4x4 M=transpose(mat);
	float m01xy=M[0].x*M[1].y-M[0].y*M[1].x;
	float m01xz=M[0].x*M[1].z-M[0].z*M[1].x;
	float m01xw=M[0].x*M[1].w-M[0].w*M[1].x;
	float m01yz=M[0].y*M[1].z-M[0].z*M[1].y;
	float m01yw=M[0].y*M[1].w-M[0].w*M[1].y;
	float m01zw=M[0].z*M[1].w-M[0].w*M[1].z;
	float m23xy=M[2].x*M[3].y-M[2].y*M[3].x;
	float m23xz=M[2].x*M[3].z-M[2].z*M[3].x;
	float m23xw=M[2].x*M[3].w-M[2].w*M[3].x;
	float m23yz=M[2].y*M[3].z-M[2].z*M[3].y;
	float m23yw=M[2].y*M[3].w-M[2].w*M[3].y;
	float m23zw=M[2].z*M[3].w-M[2].w*M[3].z;
	float4 adjM0,adjM1,adjM2,adjM3;
	adjM0.x=+dot(M[1].yzw,float3(m23zw,-m23yw,m23yz));
	adjM0.y=-dot(M[0].yzw,float3(m23zw,-m23yw,m23yz));
	adjM0.z=+dot(M[3].yzw,float3(m01zw,-m01yw,m01yz));
	adjM0.w=-dot(M[2].yzw,float3(m01zw,-m01yw,m01yz));
	adjM1.x=-dot(M[1].xzw,float3(m23zw,-m23xw,m23xz));
	adjM1.y=+dot(M[0].xzw,float3(m23zw,-m23xw,m23xz));
	adjM1.z=-dot(M[3].xzw,float3(m01zw,-m01xw,m01xz));
	adjM1.w=+dot(M[2].xzw,float3(m01zw,-m01xw,m01xz));
	adjM2.x=+dot(M[1].xyw,float3(m23yw,-m23xw,m23xy));
	adjM2.y=-dot(M[0].xyw,float3(m23yw,-m23xw,m23xy));
	adjM2.z=+dot(M[3].xyw,float3(m01yw,-m01xw,m01xy));
	adjM2.w=-dot(M[2].xyw,float3(m01yw,-m01xw,m01xy));
	adjM3.x=-dot(M[1].xyz,float3(m23yz,-m23xz,m23xy));
	adjM3.y=+dot(M[0].xyz,float3(m23yz,-m23xz,m23xy));
	adjM3.z=-dot(M[3].xyz,float3(m01yz,-m01xz,m01xy));
	adjM3.w=+dot(M[2].xyz,float3(m01yz,-m01xz,m01xy));
	float invDet=rcp(dot(M[0].xyzw,float4(adjM0.x,adjM1.x,adjM2.x,adjM3.x)));
	return transpose(float4x4(adjM0*invDet,adjM1*invDet,adjM2*invDet,adjM3*invDet));
}
```

### Mipmaps for prefix sum
D4rkpl4y3r describes in [this series of posts](https://twitter.com/d4rkpl4y3r_vr/status/1550151768067215362) how one can use mipmaps to efficiently implement compaction (or other kinds of prefix sum).

### Order of Spherical Harmonics shader coefficients
Below is a snippet describing the correspondence between the `SphericalHarmonicsL2` and the uniforms fed to shaders for probe lighting (`unity_SHAr`...`unity_SHC`):
```cs
// outCoeffs must be size 7
private void SHToShaderCoefficients(ref SphericalHarmonicsL2 sh, ref Vector4[] outCoeffs)
{
	// outCoeffs will have this order:
	// [0] = unity_SHAr
	// [1] = unity_SHAg
	// [2] = unity_SHAb
	// [3] = unity_SHBr
	// [4] = unity_SHBg
	// [5] = unity_SHBb
	// [6] = unity_SHC
	
	for (int i = 0; i < 3; i++)
	{
	    outCoeffs[i] = new Vector4(
		sh[i, 3],
		sh[i, 1],
		sh[i, 2],
		sh[i, 0] - sh[i, 6]
	    );
	
	    outCoeffs[i + 3] = new Vector4(
		sh[i, 4],
		sh[i, 5],
		sh[i, 6] * 3.0f,
		sh[i, 7]
	    );
	}
	
	outCoeffs[6] = new Vector4(
	    sh[0, 8],
	    sh[1, 8],
	    sh[2, 8],
	    1.0f
	);
}
```
