`timescale 1ns / 1ps
module tb_top_systolic_array;

    parameter DATA_WIDTH = 8;
    parameter N = 8;

    // Clock and reset
    logic clk;
    logic nrst;

    // Inputs to top module
    logic [0:N-1][DATA_WIDTH-1:0] i_ifmap;
    logic [0:N-1][DATA_WIDTH-1:0] i_weight;

    // Outputs
    wire [3:0] led;
    wire [0:N-1][DATA_WIDTH*2-1:0] o_ofmap;

    // Instantiate top module
    top_systolic_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .N(N)
    ) uut (
        .clk(clk),
        .nrst(nrst),
        .ifmap(i_ifmap),
        .weight(i_weight),
        .led(led),
        .ofmap(o_ofmap)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    
    initial begin
        #1;
        $display("TB clk = %b", clk);
    end


    // Reset
/*    initial begin
        nrst = 0;
        #10;
        nrst = 1;
    end*/

    // Feed example ifmap and weight values
/*    integer k;
    initial begin
        for (k = 0; k < N; k = k + 1) begin
            i_ifmap[k] = k + 1;   // 1..8
            i_weight[k] = 8'd1;   // all ones
        end
    end*/

    // Wait for array to propagate
    // fix this because it just keeps sending in inputs
/*    initial begin
        nrst = 0;
        i_ifmap = 0;
        i_weight = 0;
        
        #10;  // Wait for reset to release
        nrst = 1;
        
        // Now set input data AFTER reset is released
        #5;   // Wait half a clock cycle
        for (integer k = 0; k < N; k = k + 1) begin
            i_ifmap[k] = k + 1;   // 1..8
            i_weight[k] = 8'd1;   // all ones
        end
    end*/
    initial begin
        // Initialize
        nrst     = 0;
        i_ifmap  = 0;
        i_weight = 0;
    
        // Hold reset for 2 clocks
        repeat (2) @(posedge clk);
        nrst = 1;
    
        // feed k for N clk cycles
        for (int k = 0; k < N; k++) begin
            @(posedge clk);
            for (int k = 0; k < N; k++) begin
                i_ifmap[k]  = k + 1;   // 1..8
                i_weight[k] = 8'd1;    // all ones
            end
        end
    
        // Stop feeding
        @(posedge clk);
        i_ifmap  = 0;
        i_weight = 0;
    end


    // Wait for array to propagate
    initial begin
        repeat (2*N + 5) @(posedge clk);
        $display("LED output: %b", led);
        $display("Full ofmap:");
        print_ofmap();
        $finish;
    end

    // Task to print ofmap
/*    task print_ofmap;
        integer r, c;
        begin
            for (r = 0; r < N; r = r + 1) begin
                for (c = 0; c < N; c = c + 1) begin
                    $write("%0d ", o_ofmap[r][c]);
                end
                $write("\n");
            end
        end
    endtask*/
    task print_ofmap;
        integer r;
        begin
            for (r = 0; r < N; r = r + 1) begin
                $display("%0d", o_ofmap[r]);
            end
        end
    endtask


endmodule
