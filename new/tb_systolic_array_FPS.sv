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
    
    // Handshake Wires aka fake wires HAHAH
    logic tb_ir_ready = 0;
    logic tb_wr_ready = 0;
    logic tb_ir_done  = 0;
    logic tb_wr_done  = 0;
    logic tb_or_done  = 0;
    
    // state name display in the Tcl console:
    string state_name;
    initial begin
        $display("--- Monitoring Control Registers ---");
        forever begin
            // Trigger whenever registers OR the internal FSM state changes
            @(uut.layer_type or uut.C_in or uut.start_reg or uut.done or uut.tile_ctrl.state);
            
            // Translate the numeric state to a readable string
            case (uut.tile_ctrl.state)
                3'd0: state_name = "IDLE";
                3'd1: state_name = "CLEAR";
                3'd2: state_name = "ACTIVATION_ROUTING";
                3'd3: state_name = "FIFO_POP";
                3'd4: state_name = "COMPUTE";
                3'd5: state_name = "OUTPUT_ROUTING";
                default: state_name = "UNKNOWN";
            endcase

            $display("[%0t ns] SYSTEM STATUS UPDATE:", $time);
            $display("       FSM State:  %s (%0d)", state_name, uut.tile_ctrl.state);
            $display("       Layer Type: %s", uut.layer_type ? "POINTWISE (1)" : "DEPTHWISE (0)");
            $display("       C_in:       %0d", uut.C_in);
            $display("       Start Reg:  %b", uut.start_reg);
            $display("       Done:  %b", uut.done);
            $display("------------------------------------");
        end
    end

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
        
        .ifmap(ifmap),
        .weight(weight),
        
        .led(led),
        .ofmap(ofmap),
        
        // fake wires
        .i_ir_ready(tb_ir_ready),
        .i_wr_ready(tb_wr_ready),
        .i_ir_done(tb_ir_done),
        .i_wr_done(tb_wr_done),
        .i_or_done(tb_or_done)
        
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
        nrst  = 0;
        wr_en = 0; wr_addr = 0; wr_data = 0;
        ifmap  = 0; weight = 0;
        
        #20;
        nrst = 1;
        repeat (5) @(posedge clk);
        
        // Step 1: Write Registers (Moves State from IDLE -> IDLE)
        $display("Setting C_in to 8...");
        write_reg(16'h04, 32'd8); 
        $display("Setting Layer Type to 0...");
        write_reg(16'h00, 32'd0);
        
        // Step 2: Start (Moves State IDLE -> CLEAR -> ACTIVATION_ROUTING)
        $display("Triggering Start...");
        write_reg(16'h0C, 32'h1);
        
        // Step 3: Exit ACTIVATION_ROUTING
        wait(uut.tile_ctrl.state == 3'd2);
        #20;
        tb_ir_ready = 1; 
        tb_wr_ready = 1;
        
        // Step 4: Exit FIFO_POP (Moves to COMPUTE)
        wait(uut.tile_ctrl.state == 3'd3);
        #40;
        tb_ir_done = 1; 
        tb_wr_done = 1;

        // Step 5: Exit OUTPUT_ROUTING (Returns to IDLE)
        wait(uut.tile_ctrl.state == 3'd5);
        #50;
        tb_or_done = 1; 
        
        // Step 6: Wait for Control Register Auto-Clear
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
 /*   initial begin
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
    end*/
    
    // print something everytime there is a change in the variable or behavior
    // i also might turn off record waveform
    initial begin
        $monitor("Time=%0t | State=%s | Start=%b | Layer=%b | Cin=%0d | Done=%b", 
                 $time, state_name, uut.start_reg, uut.layer_type, uut.C_in, uut.done);
    end
endmodule