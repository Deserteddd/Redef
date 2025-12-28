
struct vs_in {
	float2 position : POS;
    float4 color    : COL;
};
struct vs_out {
	float4 position : SV_POSITION;
    float4 color    : COL;
};

vs_out vs_main(vs_in input) {
    vs_out output;
    output.position = float4(input.position.x, input.position.y, 0, 1);
    output.color = input.color;
	return output;
}
float4 ps_main(vs_out input) : SV_TARGET {
	return input.color;
}