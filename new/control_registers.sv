`timescale 1ns / 1ps

module control_registers(
    input  logic clk, 
    input  logic nrst,
    input  logic wr_en,
    input  logic [7:0] wr_addr,
    input  logic [31:0] wr_data,
    
    output logic layer_type, // 0 = DW, 1 = PW
    output logic [15:0] C_in,
    //output logic [31:0] weight_offset, renamed to weight base addr
    output logic start_reg,
    
    // Quantization Registers for int8
    output logic [31:0] quant_mult, // integer mult scaling
    output logic [7:0]  quant_shift, // by how many bits are we shifting (division by 2)
    
    // Registers to hold the base addresses that were instantiated in the C code
    // These are the pointers to the location in RAM
    output logic [31:0] weight_base_addr,
    output logic [31:0] ifmap_base_addr,
    output logic [31:0] bias_base_addr, 
    
    input  logic done
);
    
    always_ff @ (posedge clk or negedge nrst) begin
        if (!nrst) begin
            layer_type    <= 0;
            C_in          <= 0;
            start_reg     <= 0;
            quant_mult    <= 0;
            quant_shift   <= 0;
            weight_base_addr <= 0;
            ifmap_base_addr  <= 0;
            bias_base_addr   <= 0;
        end 
        else begin
            // Write logic
            if (wr_en) begin
                case (wr_addr)
                    8'h00: layer_type       <= wr_data[0];
                    8'h04: C_in             <= wr_data[15:0];
                    8'h08: weight_base_addr <= wr_data;
                    8'h0C: ifmap_base_addr  <= wr_data;
                    8'h10: bias_base_addr   <= wr_data;
                    8'h14: quant_shift      <= wr_data[7:0];
                    8'h18: quant_mult       <= wr_data;
                    8'h1C: start_reg        <= wr_data[0];
                endcase
            end
    
            // Auto-clear start when computation finishes
            if (done)
                start_reg <= 0;
        end
    end
endmodule