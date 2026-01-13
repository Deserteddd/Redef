
struct vs_in {
	float3 position : pos;
    float2 uv       : uv;
};
struct vs_out {
	float4 position : SV_Position;
    float2 uv       : uv;
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
	return output;
}

Texture2D tex;

SamplerState splr;

float4 ps_main(vs_out input) : SV_Target {
	return tex.Sample(splr, input.uv);
}