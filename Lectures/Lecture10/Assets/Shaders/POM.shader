Shader "Custom/POM"
{
    Properties {
        // normal map texture on the material,
        // default to dummy "flat surface" normalmap
        [KeywordEnum(PLAIN, NORMAL, BUMP, POM, POM_SHADOWS)] MODE("Overlay mode", Float) = 0
        
        _NormalMap("Normal Map", 2D) = "bump" {}
        _MainTex("Texture", 2D) = "grey" {}
        _HeightMap("Height Map", 2D) = "white" {}
        _MaxHeight("Max Height", Range(0.0001, 0.02)) = 0.01
        _StepLength("Step Length", Float) = 0.000001
        _MaxStepCount("Max Step Count", Int) = 64
        
        _Reflectivity("Reflectivity", Range(1, 100)) = 0.5
    }
    
    CGINCLUDE
    #include "UnityCG.cginc"
    #include "UnityLightingCommon.cginc"
    
    inline float LinearEyeDepthToOutDepth(float z)
    {
        return (1 - _ZBufferParams.w * z) / (_ZBufferParams.z * z);
    }

    struct v2f {
        float3 worldPos : TEXCOORD0;
        half3 worldSurfaceNormal : TEXCOORD4;
        // texture coordinate for the normal map
        float2 uv : TEXCOORD5;
        float4 clip : SV_POSITION;

        half3x3 tangentToWorld : TEXCOORD1;
        half3x3 objectToTangent : TEXCOORD6;
    };

    // Vertex shader now also gets a per-vertex tangent vector.
    // In Unity tangents are 4D vectors, with the .w component used to indicate direction of the bitangent vector.
    v2f vert (float4 vertex : POSITION, float3 normal : NORMAL, float4 tangent : TANGENT, float2 uv : TEXCOORD0)
    {
        v2f o;
        o.clip = UnityObjectToClipPos(vertex);
        o.worldPos = mul(unity_ObjectToWorld, vertex).xyz;
        half3 wNormal = UnityObjectToWorldNormal(normal);
        half3 wTangent = UnityObjectToWorldDir(tangent.xyz);

        o.uv = uv;
        o.worldSurfaceNormal = normalize(wNormal);
        
        // compute bitangent from cross product of normal and tangent and output it
        half tangentSign = tangent.w * unity_WorldTransformParams.w;
        half3 wBitangent = cross(wNormal, wTangent) * tangentSign;
        o.tangentToWorld = half3x3(wTangent.x, wBitangent.x, wNormal.x,
                                   wTangent.y, wBitangent.y, wNormal.y,
                                   wTangent.z, wBitangent.z, wNormal.z);

        half3 bitangent = cross(normal, tangent.xyz) * tangentSign;
        o.objectToTangent = half3x3(tangent.xyz, bitangent, normal);
        return o;
    }

    // normal map texture from shader properties
    sampler2D _NormalMap;
    sampler2D _MainTex;
    sampler2D _HeightMap;
    
    // The maximum depth in which the ray can go.
    uniform float _MaxHeight;
    // Step size
    uniform float _StepLength;
    // Count of steps
    uniform int _MaxStepCount;
    
    float _Reflectivity;

    void frag (in v2f i, out half4 outColor : COLOR, out float outDepth : DEPTH)
    {
        float2 uv = i.uv;
        
        float3 worldViewDir = normalize(i.worldPos.xyz - _WorldSpaceCameraPos.xyz);
#if MODE_BUMP
        // Change UV according to the Parallax Offset Mapping
        float angle_cos = dot(-worldViewDir.xyz, i.worldSurfaceNormal);
        float height = tex2D(_HeightMap, uv) * _MaxHeight;
        float cathetus = (_MaxHeight - height);
        float hypo = 1 / angle_cos * cathetus;
        float shift = (1 - angle_cos * angle_cos) * hypo;
        uv -= shift * normalize(mul(i.objectToTangent, UnityWorldToObjectDir(-worldViewDir)).xy);
#endif   
    
        float depthDif = 0;
#if MODE_POM | MODE_POM_SHADOWS    
        // Change UV according to Parallax Occclusion Mapping
        float3 uv_step_dir = normalize(mul(i.objectToTangent, UnityWorldToObjectDir(worldViewDir)));
        float point_height = _MaxHeight;
        bool need_break = false;
        float2 new_uv = uv;

        for (int j = 0; j < _MaxStepCount; j++) {
            half uv_height = tex2D(_HeightMap, new_uv) * _MaxHeight;
            if (uv_height >= point_height && !need_break) { // break does not work for some reason
                need_break = true;
            }
            if (!need_break) {
                new_uv += _StepLength * uv_step_dir.xy;
                point_height += _StepLength * uv_step_dir.z;
            }
        }

        // linear approximation
        float new_uv_height = tex2D(_HeightMap, new_uv) * _MaxHeight;
        float uv_height = tex2D(_HeightMap, uv) * _MaxHeight;
        uv = uv + (new_uv - uv) *
        clamp((new_uv_height - point_height + _MaxHeight - uv_height) / (_MaxHeight - uv_height), 0.0, 1.0);
#endif

        float3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);
        float shadow = 0;
#if MODE_POM_SHADOWS
        // Calculate soft shadows according to Parallax Occclusion Mapping, assign to shadow
#endif
        
        half3 normal = i.worldSurfaceNormal;
#if !MODE_PLAIN
        half3 tnormal = UnpackNormal(tex2D(_NormalMap, uv));
        normal = mul(i.tangentToWorld, tnormal);
#endif

        // Diffuse lightning
        half cosTheta = max(0, dot(normal, worldLightDir));
        half3 diffuseLight = max(0, cosTheta) * _LightColor0 * max(0, 1 - shadow);
        
        // Specular lighting (ad-hoc)
        half specularLight = pow(max(0, dot(worldViewDir, reflect(worldLightDir, normal))), _Reflectivity) * _LightColor0 * max(0, 1 - shadow); 

        // Ambient lighting
        half3 ambient = ShadeSH9(half4(UnityObjectToWorldNormal(normal), 1));

        // Return resulting color
        float3 texColor = tex2D(_MainTex, uv);
        outColor = half4((diffuseLight + specularLight + ambient) * texColor, 0);
        outDepth = LinearEyeDepthToOutDepth(LinearEyeDepth(i.clip.z));
    }
    ENDCG
    
    SubShader
    {    
        Pass
        {
            Name "MAIN"
            Tags { "LightMode" = "ForwardBase" }
        
            ZTest Less
            ZWrite On
            Cull Back
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile_local MODE_PLAIN MODE_NORMAL MODE_BUMP MODE_POM MODE_POM_SHADOWS
            ENDCG
            
        }
    }
}