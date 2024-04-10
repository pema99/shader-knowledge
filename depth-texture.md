# Depth texture
Various methods of using the camera depth texture (or other depth texures) and gotchas when doing so. The camera depth texture is a texture that encodes scene depth for each pixel of the screen. It can be accessed by simply declaring a texture named `_CameraDepthTexture` in your shader, but there are some things to keep in mind when using it and other depth textures (for example depth only RenderTextures).

## Worldspace from depth
Here is a shader that demonstrates using the `_CameraDepthTexture` to get the world space position of each fragment. Full shader source is [here](https://gist.github.com/pema99/b13a76508bba3e8b70caaaea920ec1c3).
```glsl
struct v2f
{
    float4 vertex : SV_Position;
    float4 clipPos : TEXCOORD0;
    nointerpolation float4x4 inverseVP : IVP;
};

UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);

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

v2f vert (float4 vertex : POSITION, float2 uv : TEXCOORD0)
{
    v2f o;
    o.vertex = float4(float2(1,-1)*(uv*2-1),1,1);
    o.clipPos = o.vertex;
    o.inverseVP = inverse(UNITY_MATRIX_VP);
    return o;
}

float4 frag (v2f i) : SV_Target
{
    float4 clipPos = i.clipPos / i.clipPos.w;
    clipPos.z = tex2Dproj(_CameraDepthTexture, ComputeScreenPos(clipPos));
    float4 homWorldPos = mul(i.inverseVP, clipPos);
    float3 wpos = homWorldPos.xyz / homWorldPos.w; // world space fragment position
    return float4(wpos, 1.0f);
}
```

## Depth based effects in mirrors
Depth based effects will show up incorrectly in VRChat mirrors without special handling due to oblique projection matrices. The shader above should handle this correctly. Alternatively, check out this older shader from DJ Lukis:

https://github.com/lukis101/VRCUnityStuffs/blob/master/Shaders/DJL/Overlays/WorldPosOblique.shader

## Normals from depth
Once you have the world space position of each fragment, you can use pixel derivatives `ddx` and `ddy` to get an approximation of the normal vector of each fragment:
```glsl
...
float3 wpos = homWorldPos.xyz / homWorldPos.w; // world space fragment position
float3 wposx = ddx(wpos);
float3 wposy = ddy(wpos);
float3 wnormal = normalize(cross(wposy,wposx)); // world space fragment normal
```

## Making shaders show up in the depth texture
For a shader to appear in the depth texture, a couple of properties must be satisfied:
- The shader/material must have `ZWrite On`.
- The shader/material must be on a render queue less or equal to 2500.
- The shader or one of it's fallbacks must have a `ShadowCaster` pass.
- There must be an active directional light in the scene. For this reason, many people put a directional light with very low intensity on their avatars when making effects that use depth; a so-called 'depth light'.

The third property can be satisfied by either adding a `ShadowCaster` pass:
```glsl
//... main pass above here
Pass
{
    Tags {"LightMode"="ShadowCaster"}

    CGPROGRAM
    #pragma vertex vert
    #pragma fragment frag
    #pragma multi_compile_shadowcaster
    #include "UnityCG.cginc"

    struct v2f
    { 
        V2F_SHADOW_CASTER;
    };

    v2f vert(appdata_base v)
    {
        v2f o;
        TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
        return o;
    }

    float4 frag(v2f i) : SV_Target
    {
        SHADOW_CASTER_FRAGMENT(i)
    }
    ENDCG
}
```

Or by adding a fallback shader which has the pass:
```glsl
SubShader
{
    ...
}
FallBack "Standard"
```

## Detecting whether shader is rendering to Camera Depth Texture
As mentioned above, a `ShadowCaster` pass is required for a shader to render to the Camera Depth Texture. Since that pass is also used to render shadows, it can be useful to disambiguate whether we are currently rendering into the Camera Depth Texture or not. That can be achieved with the following code:
```glsl
if (!dot(unity_LightShadowBias, 1))
{
    // this code will only run when rendering to camera depth texture
}
```
Thanks, Silent!

## A note on normals
The simplest way to calculate normals from depth is by taking the gradient of the reconstructed world space position using `ddx(...)` and `ddy(...)`. This works, but results in very jagged looking normals at the edges of objects. There are better, slightly more expensive ways of calculating normals, some of which are described here (praise bgolus):
- https://twitter.com/bgolus/status/1365449067770220551
- https://gist.github.com/bgolus/a07ed65602c009d5e2f753826e8078a0

## Depth buffer is reversed on Oculus Quest
When writing shaders for the quest, make sure to use the `UNITY_REVERSED_Z` macro.
For example:
```glsl
float z = /* some depth buffer value */;

#if UNITY_REVERSED_Z
z = 1.0 - z;
#endif

...
```
