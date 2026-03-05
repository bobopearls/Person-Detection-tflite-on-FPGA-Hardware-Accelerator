`timescale 1ns / 1ps

module control_registers(
    input  logic clk, 
    input  logic nrst,
    input  logic wr_en,
    input  logic [7:0] wr_addr,
    input  logic [31:0] wr_data,
    
    output logic layer_type, // 0 = DW, 1 = PW
    output logic [15:0] C_in,
    output logic [31:0] weight_offset,
    output logic start_reg,
    
    input  logic done
);
    
    always_ff @ (posedge clk or negedge nrst) begin
        if (!nrst) begin
            layer_type    <= 0;
            C_in          <= 0;
            weight_offset <= 0;
            start_reg     <= 0;
        end 
        else begin
            // Write logic
            if (wr_en) begin
                case (wr_addr)
                    8'h00: layer_type    <= wr_data[0];
                    8'h04: C_in          <= wr_data[15:0];
                    8'h08: weight_offset <= wr_data;
                    8'h0C: start_reg     <= wr_data[0];
                endcase
            end
    
            // Auto-clear start when computation finishes
            if (done)
                start_reg <= 0;
        end
    end
endmodule