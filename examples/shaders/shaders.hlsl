
struct vs_in {
	float2 position : pos;
    float4 color    : col;
};
struct vs_out {
	float4 position : SV_Position;
    float4 color    : col;
};

vs_out vs_main(vs_in input) {
    vs_out output;
    output.position = float4(input.position.x, input.position.y, 0, 1);
    output.color = input.color;
	return output;
}
float4 ps_main(vs_out input) : SV_Target {
	return input.color;
}
float4 ps_main2(vs_out input) : SV_Target {
    return 1 - input.color;
}