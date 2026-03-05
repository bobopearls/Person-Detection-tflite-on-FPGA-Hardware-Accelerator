`timescale 1ns / 1ps
module top_systolic_array #(
    parameter DATA_WIDTH = 8,
    parameter N = 8
)(
    input  logic clk,
    input  logic nrst,
    input  logic wr_en,
    input  logic [15:0] wr_addr,
    input  logic [31:0] wr_data,
    input  logic [0:N-1][DATA_WIDTH-1:0] ifmap,
    input  logic [0:N-1][DATA_WIDTH-1:0] weight,
    output logic [3:0] led,
    output logic [0:N-1][DATA_WIDTH*2-1:0] ofmap
);

    // Control signals
    logic pe_en;
    wire i_reg_clear = 1'b0;
    wire i_psum_out_en = 1'b1;
    wire i_scan_en     = 1'b0;
    wire [1:0] i_mode  = 2'b00;
    
    // From the control_registers:
    logic start_reg;
    logic layer_type;
    logic [15:0] C_in;
    logic [31:0] weight_offset;
    logic done;

    // Counter to track propagation
    logic [$clog2(2*N):0] cycle_count;
    logic valid_output;
    
    // dummy inputs test for testing control reg -> tile controller -> systolic array
    logic [0:N-1][DATA_WIDTH-1:0] dummy_ifmap; 
    logic [0:N-1][DATA_WIDTH-1:0] dummy_weight;
    
    assign dummy_ifmap = '{8'd1, 8'd2, 8'd3, 8'd4, 8'd5, 8'd6, 8'd7, 8'd8}; 
    assign dummy_weight = '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1};
    
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            cycle_count <= 0;
        end else if (pe_en) begin
            cycle_count <= cycle_count + 1; // only when the array is active
        end else begin
            cycle_count <= 0;
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
        .i_pe_en(pe_en), // tile control
        .i_psum_out_en(i_psum_out_en),
        .i_scan_en(i_scan_en),
        .i_mode(i_mode),
        /*.i_ifmap(ifmap),
        .i_weight(weight),*/
        .i_ifmap(dummy_ifmap),
        .i_weight(dummy_weight),
        .o_ofmap(ofmap)
    );
    
    // instantiate the control reg
    control_registers ctrl_reg(
        .clk(clk),
        .nrst(nrst),
        .wr_en(wr_en),
        .wr_addr(wr_addr[7:0]), // for register decoding, its 8 bits
        .wr_data(wr_data),
        
        .layer_type(layer_type),
        .C_in(C_in),
        .weight_offset(weight_offset),
        .start_reg(start_reg),
        
        .done(done)
    );
    
    // instantiate the tile controller
    tile_controller tile_ctrl(
        .i_clk(clk),
        .i_nrst(nrst),
    
        .i_route_en(start_reg),
        .i_layer_type(layer_type),
        .i_Cin(C_in),
    
        .o_pe_en(pe_en),
        .o_done(done)
    );

endmodule
