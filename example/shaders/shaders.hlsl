
struct vs_in {
	float3 position : pos;
    float4 color    : col;
};
struct vs_out {
	float4 position : SV_Position;
    float4 color    : col;
};

cbuffer Mat {
    float4x4 vp;
    float4x4 model;
};

vs_out vs_main(vs_in input) {
    vs_out output;
    
    float4 worldPosition = mul(model, float4(input.position, 1));
    output.position = mul(vp, worldPosition);
    output.color = normalize(float4(input.position, 1));
	return output;
}
float4 ps_main(vs_out input) : SV_Target {
	return input.color;
}