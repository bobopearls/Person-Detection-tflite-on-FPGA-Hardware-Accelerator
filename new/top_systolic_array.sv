`timescale 1ns / 1ps
module top_systolic_array #(
    parameter DATA_WIDTH = 8,
    parameter N = 8
)(
    input  logic clk,
    input  logic nrst,
    input  logic [0:N-1][DATA_WIDTH-1:0] ifmap,
    input  logic [0:N-1][DATA_WIDTH-1:0] weight,
    output logic [3:0] led,
    output logic [0:N-1][DATA_WIDTH*2-1:0] ofmap
);

    // Control signals
    logic i_pe_en;
    wire i_reg_clear = 1'b0;
    wire i_psum_out_en = 1'b1;
    wire i_scan_en     = 1'b0;
    wire [1:0] i_mode  = 2'b00;
    
    // From the layer_controller:
    logic start_tile;
    logic layer_type;
    logic [15:0] Cin;
    logic [31:0] weight_offset;
    logic tile_done;
    logic inference_done;

    // Counter to track propagation
    logic [$clog2(2*N):0] cycle_count;
    logic valid_output;

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            i_pe_en <= 1'b0;
            cycle_count <= 0;
        end else begin
            i_pe_en <= 1'b1;        // enable the systolic array
            cycle_count <= cycle_count + 1;
        end
    end

    assign valid_output = (cycle_count >= (N + N - 1));
    assign led = valid_output ? ofmap[0][3:0] : 4'b0000;

    // Instantiate the systolic array
    systolic_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .WIDTH(N),
        .HEIGHT(N)
    ) dut (
        .i_clk(clk),
        .i_nrst(nrst),
        .i_reg_clear(i_reg_clear),
        .i_pe_en(i_pe_en),
        .i_psum_out_en(i_psum_out_en),
        .i_scan_en(i_scan_en),
        .i_mode(i_mode),
        .i_ifmap(ifmap),
        .i_weight(weight),
        .o_ofmap(ofmap)
    );
    
    // instantiate the layer_controller
    layer_controller u_layer_ctrl (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_start(i_start),
    
        .i_tile_done(tile_done),
    
        .o_start_tile(start_tile),
        .o_layer_type(layer_type),
        .o_Cin(Cin),
        .o_weight_offset(weight_offset),
    
        .o_done(inference_done)
    );

endmodule
