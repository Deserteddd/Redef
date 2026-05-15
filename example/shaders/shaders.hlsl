
struct vs_in {
	float3 position : pos;
    float2 uv       : uv;
};
struct vs_out {
	float4 position : SV_Position;
    float2 uv       : uv;
    float3 world_pos: world_pos;
    float3 normal   : normal;
};

cbuffer Vp {
    float4x4 vp;
};

cbuffer Model {
    float4x4 model;
}


vs_out vs_main(vs_in input) {
    vs_out output;

    float4 worldPosition = mul(model, float4(input.position, 1));
    output.position = mul(vp, worldPosition);
    output.uv = input.uv;

    // Meshes in this project are sphere-like, so position is a reasonable proxy normal.
    float3 localNormal = normalize(input.position);
    output.normal = normalize(mul((float3x3)model, localNormal));
    output.world_pos = worldPosition.xyz;
	return output;
}



cbuffer Camera {
    float3 camera_pos;
}

struct PointLight {
    float3 position;
    float  intensity;

    float3 color;
    float  range;

    float attenuation_constant;
    float attenuation_linear;
    float attenuation_quadratic;
    float _pad0;
};

cbuffer Lighting {
    PointLight point_light;
};

struct Color {
    float3 color;
};

cbuffer ColorIdx {
    uint color_index;
}


Texture2D tex : register(t0);
SamplerState splr : register(s0);
StructuredBuffer<Color> colors : register(t1);

float compute_attenuation(float distance_to_light) {
    float attenuation = 1.0 / max(
        point_light.attenuation_constant + point_light.attenuation_linear * distance_to_light + point_light.attenuation_quadratic * distance_to_light * distance_to_light,
        0.0001
    );
    if (point_light.range > 0.0) {
        attenuation *= saturate(1.0 - distance_to_light / point_light.range);
    }
    return attenuation * point_light.intensity;
}

float4 ps_main(vs_out input) : SV_Target {
	const float ambient_strength = 0.08;
    const float diffuse_wrap = 0.08;
    const float specular_strength = 0.04;
    const float shininess = 96.0;

	float3 albedo = tex.Sample(splr, input.uv).rgb;
    float3 normal = normalize(input.normal);
    float3 to_light = point_light.position - input.world_pos;
    float distance_to_light = length(to_light);
    float3 light_dir = distance_to_light > 0.0001 ? (to_light / distance_to_light) : float3(0, 0, 0);

    float attenuation = compute_attenuation(distance_to_light);

    float ndotl = saturate(dot(normal, light_dir));
    float wrapped_ndotl = saturate((ndotl + diffuse_wrap) / (1.0 + diffuse_wrap));
    float3 diffuse = wrapped_ndotl * point_light.color * albedo;

    float3 view_dir = normalize(camera_pos - input.world_pos);
    float ndotv = saturate(dot(normal, view_dir));
    float3 half_dir = normalize(light_dir + view_dir);
    float spec = (ndotl > 0.0 && ndotv > 0.0) ? pow(saturate(dot(normal, half_dir)), shininess) : 0.0;
    spec *= ndotl * ndotv;
    float3 dielectric_f0 = float3(0.02, 0.02, 0.02);
    float3 specular = specular_strength * spec * dielectric_f0 * point_light.color;

    float3 ambient = ambient_strength * albedo;
    float3 color = ambient + attenuation * (diffuse + specular);
    return float4(saturate(color), 1.0);
}

float4 ps_sun(vs_out input) : SV_Target {
    float3 albedo = tex.Sample(splr, input.uv).rgb;
    float3 normal = normalize(input.normal);
    float3 view_dir = normalize(camera_pos - input.world_pos);

    // Fresnel-like rim term adds a soft halo near the silhouette.
    float rim = pow(1.0 - saturate(dot(normal, view_dir)), 2.5);
    float3 glow = albedo * 1.8 + float3(1.0, 0.65, 0.25) * rim * 0.9;
    return float4(saturate(glow), 1.0);
}


float4 ps_orbit_band(vs_out input) : SV_Target {
    return float4(normalize(colors[color_index].color), 0.28);
}