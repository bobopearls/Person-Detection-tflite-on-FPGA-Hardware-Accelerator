module systolic_array_FPS#(
    parameter DATA_WIDTH = 8,
    parameter WIDTH = 8,
    parameter HEIGHT = 8
) (
    input logic clk, nrst, start,
    output logic done
);

    logic [31:0] cycle_count;
    logic running;
    
    always_ff @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            cycle_count <= 0;
            running <= 0;
        end else begin
            if (start) // if strrat = 1
                running <= 1;
            if (done)
                running <= 0;
            if (running)
                cycle_count <= cycle_count + 1; // incrementing per clk cycle
        end 
    end
    
    
endmodule