
struct vs_in {
	float3 position : pos;
};
struct vs_out {
	float4 position : SV_Position;
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
	return output;
}

cbuffer Palette {
    float3 colors[6];
}

float4 ps_main(uint tid : SV_PrimitiveID) : SV_Target {
	return float4(colors[tid % 6], 1);
}