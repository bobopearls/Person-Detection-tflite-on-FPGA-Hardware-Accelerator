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
    
    //Handshake pins (will need to replace this with DMA signals sometime soon)
    input  logic i_ir_ready,
    input  logic i_wr_ready,
    input  logic i_ir_done,
    input  logic i_wr_done,
    input  logic i_or_done,
    
    output logic [3:0] led,
    output logic [0:N-1][DATA_WIDTH-1:0] ofmap
);

    // Control signals from systolic array
    logic [0:N-1][DATA_WIDTH*2-1:0] raw_ofmap; 
    logic pe_en;
    logic psum_out_en;
    logic [2:0] o_state; 
    
    // Control Register Outputs
    logic start_reg;
    logic layer_type;
    logic [15:0] C_in;
    logic [31:0] weight_base_addr, ifmap_base_addr, bias_base_addr;
    logic [31:0] quant_mult;
    logic [7:0]  quant_shift;
    logic done;
    
    
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
        .i_psum_out_en(psum_out_en),
        .i_scan_en(i_scan_en),
        .i_mode(i_mode),
        .i_ifmap(ifmap),
        .i_weight(weight),
        .o_ofmap(raw_ofmap)
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
        .start_reg(start_reg),
        
        .weight_base_addr(weight_base_addr),
        .ifmap_base_addr(ifmap_base_addr),
        .bias_base_addr(bias_base_addr),
        
        .quant_mult(quant_mult),
        .quant_shift(quant_shift),
        
        .done(done)
    );
    
    // instantiate the tile controller
    tile_controller #(
        .ROWS(N),
        .COLUMNS(N),
        .ADDR_WIDTH(16)
    )tile_ctrl(
        .i_clk(clk),
        .i_nrst(nrst),
        .i_reg_clear(i_reg_clear),
        .i_route_en(start_reg),
        .i_layer_type(layer_type),
        .i_Cin(C_in),
        
        // top level pins to connect to the controller
        .i_ir_ready(i_ir_ready), // connect to the FSM in
        .i_wr_ready(i_wr_ready),
        
        .i_ir_context_done(i_ir_done), // Bridges the 'done' pin to the 'context' logic
        .i_wr_context_done(i_wr_done),
        .i_or_done(i_or_done),
        
        // outputs:
        .o_pe_en(pe_en),
        .o_psum_out_en(psum_out_en),
        .o_done(done),
        .o_state(o_state)
    );
    
    // We process the 16-bit P-Sums from the array into 8-bit outputs
    genvar i;
    generate
        for (i = 0; i < N; i++) begin : gen_quant
            logic [31:0] bias_added;
            logic [63:0] scaled; // High precision for multiplication
            
            always_comb begin
                // A. Add Bias (16-bit bias added to 16-bit raw sum)
                // Note: Real MobileNet uses bias_base_addr to fetch from memory; 
                // here we use the lower 16 bits of the register as a placeholder.
                bias_added = raw_ofmap[i] + bias_base_addr[15:0];
                
                // B. Scale (Quantization Multiply)
                scaled = bias_added * quant_mult;
                
                // C. Shift and Clip to 8-bit (INT8 range 0-255 or -128-127)
                // Using logical shift and simple truncation for now
                if (psum_out_en) begin
                    ofmap[i] = (scaled >> quant_shift);
                end else begin
                    ofmap[i] = 0;
                end
            end
        end
    endgenerate
    
    assign led = done ? 4'b1111 : 4'b0000;
    /*// Counter to track propagation
    logic [$clog2(2*N):0] cycle_count;
    logic valid_output;

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            cycle_count <= 0;
        end else if (pe_en) begin
            cycle_count <= cycle_count + 1; // only when the array is active
        end else begin
            cycle_count <= 0;
        end
    end

    assign valid_output = (cycle_count >= (N + N - 1));*/
endmodule