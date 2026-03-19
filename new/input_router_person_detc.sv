module input_router #( 
    parameter DATA_WIDTH = 8,
    parameter N = 8
) (
    input logic clk,
    input logic nrst,
    input logic i_pop_en, 
    input logic layer_type, // 0 for PW, 1 for DW
    input logic [1:0] stride,
    input  logic [0:N-1][DATA_WIDTH-1:0] ifmap_in,
    output logic [0:N-1][DATA_WIDTH-1:0] row_out
);

    logic [DATA_WIDTH-1:0] delay_line [1:N-1][1:(N-1)*2]; 

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            // Initialize EVERYTHING to 0 to prevent XXXX output in the PE
            for (int r = 1; r < N; r++) begin
                row_out[r] <= 0;
                for (int s = 1; s <= (N-1)*2; s++) begin
                    delay_line[r][s] <= 0;
                end
            end
        end
        else if (i_pop_en) begin
            // --- DEPTHWISE MODE ---
            if (layer_type == 1'b0) begin : DEPTHWISE_STALL
                row_out[0] <= ifmap_in[0];
                
                for (int r = 1; r < N; r++) begin : row_loop
                    // Shift Data In
                    delay_line[r][1] <= ifmap_in[0];
                    
                    // Shift through all possible stages (up to 14 for N=8)
                    for (int s = 2; s <= (N-1)*2; s++) begin : stage_loop
                        delay_line[r][s] <= delay_line[r][s-1];
                    end
                    
                    // Mux logic for Stride selection
                    if (stride == 2'd2)
                        row_out[r] <= delay_line[r][r*2];
                    else
                        row_out[r] <= delay_line[r][r];
                end
            end 
            // --- POINTWISE MODE ---
            else begin : POINTWISE_STALL
                for (int i = 0; i < N; i++) begin
                    row_out[i] <= ifmap_in[i];
                end
            end
        end
    end
endmodule