module input_router #(
    parameter DATA_WIDTH = 8,
    parameter N=8
) (
    input logic clk,
    input logic  layer_type, // 0 for PW, 1 for DW
    input logic [1:0] stride,
    input  logic [0:N-1][DATA_WIDTH-1:0] ifmap_in,
    output logic [0:N-1][DATA_WIDTH-1:0] row_out
);

    logic [DATA_WIDTH-1:0] delay_line [1:N-1][1:(N-1)*2]; // 2d array of registers
    // multiplexer im thinking ?
    always_ff @(posedge clk) begin
        if (layer_type) begin : DEPTHWISE_STALL
            row_out[0] <= ifmap_in[0];
            
            for (int r = 1; r < N; r++) begin : row_loop // r for row
                delay_line[r][1] <= ifmap_in[0];
                
                for (int s = 2; s <= r; s++) begin: stage_loop
                    delay_line[r][s] <= delay_line[r][s-1];
                end
                
                //mux logic: if stride is 1, take from stage 1 then 2
                // if stride is 2, take from stage 2, stage 4 etc
                if(stride == 2'd2)
                    row_out[r] <= delay_line[r][r*2];
                else if (stride == 2'd1)
                    row_out[r] <= delay_line[r][r];
            end
        end else begin : POINTWISE_STALL
            // 1-to-1 mapping
            for (int i=0; i<N; i++) begin
                row_out[i] <= ifmap_in[i];
            end
        end
    end
endmodule