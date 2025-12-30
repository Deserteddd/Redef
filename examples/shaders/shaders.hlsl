
struct vs_in {
	float2 position : pos;
    float4 color    : col;
};
struct vs_out {
	float4 position : SV_Position;
    float4 color    : col;
};

cbuffer Mat {
    matrix mat;
};

vs_out vs_main(vs_in input) {
    vs_out output;
    float4 multiplied = mul(float4(input.position.xy, 0, 1), mat);
    
    output.position = float4(input.position.xy, 0, 1);
    output.position = multiplied;
    output.color = input.color;
	return output;
}
float4 ps_main(vs_out input) : SV_Target {
	return input.color;
}