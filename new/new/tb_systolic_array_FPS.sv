`timescale 1ns / 1ps
module tb_top_systolic_array;

    parameter DATA_WIDTH = 8;
    parameter N = 8;

    // Clock and reset
    logic clk;
    logic nrst;

    // Inputs to top module
    logic [0:N-1][DATA_WIDTH-1:0] ifmap;
    logic [0:N-1][DATA_WIDTH-1:0] weight;

    logic wr_en;
    logic [15:0] wr_addr;
    logic [31:0] wr_data;
    
    // Outputs
    logic [3:0] led; 
    logic [0:N-1][DATA_WIDTH*2-1:0] ofmap;

    // --------------------------------------------------
    // DUT
    // --------------------------------------------------
    top_systolic_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .N(N)
    ) uut (
        .clk(clk),
        .nrst(nrst),
        
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        
        .ifmap(i_ifmap),
        .weight(i_weight),
        
        .led(led),
        .ofmap(o_ofmap)
    );

    // --------------------------------------------------
    // Clock generator
    // --------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    // --------------------------------------------------
    // Reset
    // --------------------------------------------------
    initial begin
        // Initialize
        nrst     = 0;
        wr_en = 0;
        wr_addr = 0;
        wr_data = 0;
        
        ifmap  = 0;
        weight = 0;
        #20;
        nrst = 1;
        
    
        // Hold reset for 5 clocks
        repeat (5) @(posedge clk);
        
        $display("Setting C_in to 8...");
        write_reg(16'h04, 32'd8); 
        $display("Setting Layer Type to 0 (Depthwise)...");
        write_reg(16'h00, 32'd0);
        $display("Triggering Start...");
        write_reg(16'h0C, 32'h1);
        
        
        wait(uut.done == 1);
        $display("Computation Finished!");
        
        #100;
        $finish;
    end
    // Task for writing to registers (some random values)
    task write_reg(input [15:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            wr_en = 1;
            wr_addr = addr;
            wr_data = data;
            @(posedge clk);
            wr_en = 0;
        end
    endtask
    
    // Monitor Control Registers Printing on the Tcl Console
    initial begin
        $display("--- Monitoring Control Registers ---");
        forever begin
            // Wait for any of the control signals to change
            @(uut.layer_type or uut.C_in or uut.start_reg or uut.done);
            
            $display("[%0t ns] REG UPDATE:", $time);
            $display("       Layer Type: %s", uut.layer_type ? "POINTWISE (1)" : "DEPTHWISE (0)");
            $display("       C_in:       %0d", uut.C_in);
            $display("       Start Reg:  %b", uut.start_reg);
            $display("       Done Flag:  %b", uut.done);
            $display("------------------------------------");
        end
    end
    
    // print something everytime there is a change in the variable or behavior
    // i also might turn off record waveform
    initial begin
        $monitor("Time=%0t | Start=%b | Layer=%b | Cin=%0d | Done=%b", 
                 $time, uut.start_reg, uut.layer_type, uut.C_in, uut.done);
    end


  /*  // Wait for array to propagate
    initial begin
        repeat (2*N + 5) @(posedge clk);
        $display("LED output: %b", led);
        $display("Full ofmap:");
        print_ofmap();
        $finish;
    end*/

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
/*    task print_ofmap;
        integer r;
        begin
            for (r = 0; r < N; r = r + 1) begin
                $display("%0d", o_ofmap[r]);
            end
        end
    endtask*/


endmodule
