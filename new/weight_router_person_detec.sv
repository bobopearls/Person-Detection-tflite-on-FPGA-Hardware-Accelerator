`timescale 1ns / 1ps
// needs to be compatible for the DW and PW switching 
// 1. check the layer type using i_layer_type
// 2. if PW do this else if DW do that
// 3. PW and DW load their weights differently
// 3.1 pointwise you need to flash the weights to save cycles
//     depthwise you need to wait in order to get the spaces to align properly
module weight_router #(
    parameter DATA_WIDTH = 8,
    parameter N = 8
)(
    input  logic clk,
    input  logic nrst,
    input  logic i_layer_type, // 0 for DW, 1 for PW
    input  logic i_pop_en, // Connected to tile_ctrl.o_wr_pop_en
    input  logic [0:N-1][DATA_WIDTH-1:0] w_data, // Raw weights from  .mem file
    output logic [0:N-1][DATA_WIDTH-1:0] o_weight // Staggered weights to Systolic Array
);

    // Staggering registers: Column 'j' needs a delay of 'j' cycles
    logic [DATA_WIDTH-1:0] delay_pipe [0:N-1][0:N-1];

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) delay_pipe[i][j] <= 0;
            end
        end else if (i_pop_en) begin
            for (int col = 0; col < N; col++) begin
                if (i_layer_type == 1'b0) begin: DW_MODE
                    // only weights to one col, PEs will shift them around 
                    delay_pipe[col][0] <= w_data[0];
                end else if (i_layer_type == 1'b1) begin: PW_MODE
                    // columns get their own weights
                    delay_pipe[col][0] <= w_data[col];
                end
                
                // shifting for weights in general (think of it as a staircase)
                /*[10 20 30 40]
                we get 10 20 30 40 then 0 20 30 40, 0 0 30 40, 0 0 0 40*/
                for (int stage = 1; stage < N; stage++) begin
                    delay_pipe[col][stage] <= delay_pipe[col][stage-1];
                end
            end
        end
    end

    // Assign the output for each column 'g' from its corresponding delay stage 'g'
    genvar g;
    generate
        for (g = 0; g < N; g++) begin : gen_weight_stagger
            assign o_weight[g] = delay_pipe[g][g];
        end
    endgenerate

endmodule