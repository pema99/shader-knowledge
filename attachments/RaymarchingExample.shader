Shader "Pema99/Raymarching Example"
{
    Properties
    {
        _Iterations ("Max iterations", Float) = 75
        _MaxDist ("Max distance", Float) = 50
        _MinDist ("Min distance", Float) = 0.001
        [ToggleUI] _WorldSpace ("March in world space?", Float) = 0
    }
    SubShader
    {
        Tags { "Queue"="Transparent" "DisableBatching"="True" }
        Pass
        {
            Cull Front // Only render backfaces, we don't anything more

            CGPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            float _WorldSpace; // March in world space?
            float _Iterations; // Max iteration count for raymarching loop.
            float _MinDist;    // Distance at which we stop raymarching, because we are 'close enough'.
            float _MaxDist;    // Distance at which we stop rayamrching, because we have 'gone too far'.

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 camera_position : TEXCOORD0;  // Position of rendering camera in either world or object space
                float3 surface_position : TEXCOORD1; // Position of a given fragment in either world or object space
            };

            v2f vert (appdata_base v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);

                // Here was pass through the camera and fragment position, both in either world or object space, depending on
                // which space we plan to raymarch in. Marching in object space will cause the rendered geometry to move 
                // with the whatever renderer the shader is applied to. When marching in world space, that isn't the case.
                if (_WorldSpace)
                {
                    o.camera_position = _WorldSpaceCameraPos;
                    o.surface_position = mul(unity_ObjectToWorld, v.vertex);
                }
                else
                {
                    o.camera_position = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1));
                    o.surface_position = v.vertex;
                }

                return o;
            }

            // A signed distance function (SDF) for a simple sphere centered at the origin.
            // SDFs take in a position, and return the distance from the surface described by the SDF to that position.
            // You can find more SDFs here: https://iquilezles.org/articles/distfunctions/ 
            float sphere_sdf(float3 position, float radius)
            {
                return length(position) - radius;
            }

            // An operator for combining multiple SDFs in a meaningful way. This will one union two SDFs, in a way
            // that produces a nice smooth transition where they intersect. Don't worry about not understanding the math.
            // More operators here: https://iquilezles.org/articles/distfunctions/
            // Explanation of smooth union: https://iquilezles.org/articles/smin/
            float operator_smooth_union(float d1, float d2, float k)
            {
                float h = clamp(0.5 + 0.5 * (d2-d1) / k, 0.0, 1.0);
                return lerp(d2, d1, h) - k * h * (1.0 - h);
            }
            
            // The signed distance function for the entire 'scene' we wish to raymarch.
            // Often named 'map' by convention. Again, takes in a position, and returns the
            // distance from the scene to that position.
            float map(float3 position)
            {
                // Calculate the distances to 2 differently sized spheres placed at 2 different positions. 
                // Instead of 'moving the spheres', we move the position at which we evaluate the SDF, which
                // has the same effect.
                float d1 = sphere_sdf(position + float3(0.2, 0.0, 0.0), 0.22);
                float d2 = sphere_sdf(position - float3(0.2, 0.0, 0.0), 0.3);

                // Return the smooth union of the 2 spheres, effectively creating 'metaballs'.
                return operator_smooth_union(d1, d2, 0.05);
            }
            
            // This function calculates the normal of the raymarched scene at a specific point in space.
            // It does so by numerically estimating the gradient of the distance function, by sampling it
            // at a few 'jittered' positions, and normalizing the result.
            // More info here: https://iquilezles.org/articles/normalsSDF/
            float3 normal(float3 position)
            {
                float2 offset = float2(0, 0.02);
                return normalize(float3(
                    map(position + offset.yxx) - map(position - offset.yxx),
                    map(position + offset.xyx) - map(position - offset.xyx),
                    map(position + offset.xxy) - map(position - offset.xxy)
                ));
            }

            // The main raymarching loop. Given a ray origin and ray direction, shoot a ray into the scene
            // and determine how far it travelled before hitting a surface, as well as how many steps it took.
            // In short, the algorithm works by repeatedly taking small steps along the direction of a ray.
            // The distance to step at each iteration is simply the distance to the nearest surface in the scene.
            // By stepping only this distance, we know that we can't possible intersect or penetrate anything -
            // it is 'safe' to move that distance along the ray.
            // A more in depth explanation of the algorithm: https://jamie-wong.com/2016/07/15/ray-marching-signed-distance-functions/
            float2 march(float3 ray_origin, float3 ray_direction)
            {
                float total_distance = 0; // How far along the ray we have travelled thus far.
                for (uint i = 0; i < _Iterations; i++)
                {
                    // Calculate at which point on the ray we currently are.
                    float3 current_position = ray_origin + ray_direction * total_distance;
                    // Calculate the distance from the scene to that point.
                    float current_distance = map(current_position);
                    // Add that to the total distance travelled - we can safely walk this distance without hitting anything.
                    total_distance += current_distance;
                    // If we have reached our set maximum distance, or we are sufficiently close to a surface, stop marching.
                    if (total_distance > _MaxDist || current_distance < _MinDist)
                    {
                        break;
                    }
                }
                // Return the distance travelled and steps taken.
                return float2(total_distance, i);
            }

            float4 frag (v2f i, out float depth : SV_Depth) : SV_Target
            {
                // Ray origin is just the current camera position.
                float3 ray_origin = i.camera_position;
                // The ray direction is the normalized vector going from camera position fragment position.
                // In other words, it's a vector pointing towards the pixel we are shading.
                float3 ray_direction = normalize(i.surface_position - i.camera_position);
                
                // Execute the marching loop and grab the results - distance travelled and steps taken.
                float2 result = march(ray_origin, ray_direction);
                float total_distance = result.x;
                float steps_taken = result.y;
                
                // If we went past our max distance, throw away the pixel and let it be transparent.
                if (total_distance >= _MaxDist)
                {
                    discard;
                }

                // Calculate the position at which our ray hit the scene,
                // and the normal of the surface at that position.
                float3 hit_position = ray_origin + ray_direction * total_distance;
                float3 hit_normal = normal(hit_position);

                // Output a depth value, so that our raymarched geometry will interact with regular rasterized
                // geometry. To do this, we must bring our intersection point into clip space, get the Z value (distance along the forward direction),
                // and perform a perspective divide to account for perspective projection.
                // Some notes on perspective projection: https://jsantell.com/model-view-projection/
                // More notes: https://www.learnopengles.com/tag/perspective-divide/
                float4 clip_position;
                if (_WorldSpace)
                {
                    clip_position = mul(UNITY_MATRIX_VP, float4(hit_position, 1.0));
                }
                else
                {
                    clip_position = UnityObjectToClipPos(float4(hit_position, 1.0));
                }
                depth = clip_position.z / clip_position.w; // The elusive perspective projection.

                // Finally, we can shade our raymarched surface. First, let's base the color off the calculated normal,
                // but do some math to map from [-1;1] to [0;1] since we can't see negative colors
                float3 base_color = hit_normal * 0.5 + 0.5; 
                
                // Here's a nifty trick, if you divide the steps taken during marching with a constant (often some multiple
                // of the max iteration count), you get a nice approximation of ambient occlusion. This essentially works
                // because it takes more steps for the raymarching algorithm to walk through tight crevices.
                float ambient_occlusion = 1.0 - (steps_taken / _Iterations);

                // Multiply fake ambient occlusion onto the base color to get the final color.
                // You could do whatever kind of shading you want here, such as simple lighting, reflection, whatever.
                // The normal vector and hit position are pretty much all you'll need.
                return float4(base_color * ambient_occlusion, 1);
            }
            ENDCG
        }
    }
}
