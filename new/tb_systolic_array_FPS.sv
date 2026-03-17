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
    
    // Handshake Wires
    logic tb_ir_ready = 0;
    logic tb_wr_ready = 0;
    logic tb_ir_done  = 0;
    logic tb_wr_done  = 0;
    logic tb_or_done  = 0;
    
    // Storage for the .mem files of person_detection.tflite
    // the .mem files have 1 value per line
    logic [DATA_WIDTH-1:0] weight_mem_raw [0:4095]; // depth of 4096
    logic [DATA_WIDTH-1:0] ifmap_mem_raw [0:4095];
    logic [DATA_WIDTH*2-1:0] bias_mem [0:511];
    
    // pointer for current byte index
    integer weight_pointer = 0;
    integer ifmap_pointer = 0;
    
    initial begin
        // Load the one-value-per-line .mem files
        $readmemh("MobilenetV1_Conv2d_0_weights_read.mem", weight_mem_raw);
        $readmemh("video_input_fake.mem", ifmap_mem_raw);
        $readmemh("MobilenetV1_MobilenetV1_Conv2d_0_Conv2D_bias.mem", bias_mem);
        $display("--- Person Detection Data Loaded ---");
    end
    
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
/*
            $display("[%0t ns] SYSTEM STATUS UPDATE:", $time);
            $display("       FSM State:  %s (%0d)", state_name, uut.tile_ctrl.state);
            $display("       Layer Type: %s", uut.layer_type ? "POINTWISE (1)" : "DEPTHWISE (0)");
            $display("       C_in:       %0d", uut.C_in);
            $display("       Start Reg:  %b", uut.start_reg);
            $display("       Done:  %b", uut.done);
            $display("------------------------------------");*/
        end
    end
    
    // UPDATED TO MAKE IT FOR 1 CHANNEL GREYSCALE:
    // need to slice the memory to fit the systolic array's NxN matrix
    // EDIT: this is the reason why the inputs and weights were read weirdly
    always @(posedge clk) begin
        if(uut.tile_ctrl.state == 3'd3 && uut.tile_ctrl.o_ir_pop_en) begin 
            // 1. IFMAP Logic: only channel 0 gets the data
            ifmap[0] <= ifmap_mem_raw[ifmap_pointer];
            
            // 2. Zero padding for the rest of the channels (1 to 7)
            for (int k = 1; k < N; k++) begin
                ifmap[k] <= 8'h00;
            end
            
            // 3. Weight Logic: one weight per output filter
            for (int j = 0; j < N; j++) begin
                weight[j] <= weight_mem_raw[weight_pointer + j];
            end
            
            // 4. Update pointers
            ifmap_pointer  <= ifmap_pointer + 1;  // Advance by 1 pixel for B&W
            weight_pointer <= weight_pointer + N; // Advance by N weights
            
        end else if (uut.tile_ctrl.state == 3'd0) begin
            // Reset pointers when in IDLE
            ifmap_pointer <= 0;
            weight_pointer <= 0;
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
        $display("Setting C_in to 9...");
        write_reg(8'h04, 32'd9);  // Cin
        $display("Setting Quantization w/ Mult 1024 and Shift 10...");
        write_reg(16'h14, 32'd10); // quant shift
        write_reg(16'h18, 32'd1024); // quant mult
        
        // Fake Base Addresses:
        $display("Setting Dummy Base Addresses...");
        write_reg(8'h08, 32'hA000); // weight_base_addr
        write_reg(8'h0C, 32'hB000); // ifmap_base_addr
        
        // Step 2: Start (Moves State IDLE -> CLEAR -> ACTIVATION_ROUTING)
        $display("Triggering Start...");
        write_reg(8'h1C, 32'h1);
        
        // Step 3: Exit ACTIVATION_ROUTING
        wait(uut.tile_ctrl.state == 3'd2);
        #20;
        tb_ir_ready = 1; 
        tb_wr_ready = 1;
        
        $display("Setting Bias Base Addr and Params...");
        write_reg(8'h10, 32'h0000_0005); // Bias of 5 (added to every output)
        write_reg(8'h14, 32'd8);        // quant_shift = 8
        write_reg(8'h18, 32'd256);      // quant_mult = 256 (Effectively Scale = 1.0)
        
        // Step 4: Exit FIFO_POP (Moves to COMPUTE)
        wait(uut.tile_ctrl.state == 3'd3);
        // wait for pointers to finish
        wait(ifmap_pointer >= 9);
        #20;
        tb_ir_done = 1; 
        tb_wr_done = 1;
        
        wait(uut.tile_ctrl.state == 3'd5); // Wait for OUTPUT_ROUTING
        $display("Computation Done. Signaling Output Router...");
        #100;
        tb_or_done = 1; // Trigger the transition back to IDLE
        #20;
        tb_or_done = 0;

        // Step 5: Exit OUTPUT_ROUTING (Returns to IDLE)
        wait(uut.tile_ctrl.state == 3'd5);
        #50;
        tb_or_done = 1; 
        
        // Step 6: Wait for Control Register Auto-Clear
        wait(uut.done == 1);
        $display("Final Verification: OFMAP[0] = %h", ofmap[0]);
        
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