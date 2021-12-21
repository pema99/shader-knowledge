# Depth texture
Various methods of using the camera depth texture (or other depth texures) and gotchas when doing so. The camera depth texture is a texture that encodes scene depth for each pixel of the screen. It can be accessed by simply declaring a texture named `_CameraDepthTexture` in your shader, but there are some things to keep in mind when using it and other depth textures (for example depth only RenderTextures).

## Worldspace from depth
You can get world space position and normal from the camera depth texture. Here is an example of how to do it. Not sure where this code came from initially, but credits to whoever wrote it. I think it was error.mdl. Keep in mind this will break in mirrors. An alternative method is shown in the following section.

```glsl
struct v2f
{
    float2 uv : TEXCOORD0;
    float4 vertex : SV_POSITION;
    float4 grabPos : TEXCOORD1;
    float3 ray : TEXCOORD2;
};

sampler2D _CameraDepthTexture;

v2f vert (appdata v)
{
    v2f o;
    o.vertex = UnityObjectToClipPos(v.vertex);
    o.uv = v.uv;
    o.grabPos = ComputeScreenPos(o.vertex);
    o.ray = mul(UNITY_MATRIX_MV, v.vertex).xyz * float3(-1,-1,1);
    return o;
}

float4 frag (v2f i) : SV_Target
{
    float rawDepth = DecodeFloatRG(tex2Dproj(_CameraDepthTexture, i.grabPos));
    float linearDepth = Linear01Depth(rawDepth);
    i.ray = i.ray * (_ProjectionParams.z / i.ray.z);
    float4 vpos = float4(i.ray * linearDepth, 1);
    float3 wpos = mul(unity_CameraToWorld, vpos).xyz; // world space frament position
    float3 wposx = ddx(wpos);
    float3 wposy = ddy(wpos);
    float3 normal = normalize(cross(wposy,wposx)); // world space fragment normal
    ...
```

## Depth based effects in mirrors
Depth based effects will show up incorrectly in VRChat mirrors without special handling. For an example on how to do this handling, check Lukis shader here:

https://github.com/lukis101/VRCUnityStuffs/blob/master/Shaders/DJL/Overlays/WorldPosOblique.shader

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
