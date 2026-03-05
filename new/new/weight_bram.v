`timescale 1ns / 1ps

module weight_bram #(
    parameter DEPTH = 4096
)(
    input  logic clk,
    input  logic [$clog2(DEPTH)-1:0] addr, // take the addr 
    output logic signed [7:0] dout
);

logic signed [7:0] mem [0:DEPTH-1]; // all weights stored linearly 
                                    // and the address index is the order of weights

initial begin
    $readmemh("MobilenetV1_Conv2d_4_pointwise_weights_read.mem", mem);
end

always_ff @(posedge clk)
    dout <= mem[addr];

endmodule