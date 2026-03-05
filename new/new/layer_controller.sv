`timescale 1ns / 1ps

// top controller will exec one tile
// layer controller needs to do the ff:
// store layer config
// provide the layer type
// provide the C_in
// weight offset, enable the tile exec, wait for o_done, then next layer

// tldr: go through the layers and then feed the info to the tile controller

typedef struct packed {
    logic [1:0] layer_type;   // 0=DW, 1=PW
    logic [15:0] Cin;
    logic [15:0] Cout;
    logic [15:0] H;
    logic [15:0] W;
    logic [31:0] weight_offset;
} layer_cfg_t;

module layer_controller #(
    parameter int NUM_LAYERS = 4 // this can be adjusted too
)(
    input logic i_clk,
    input logic i_nrst,

    input logic i_start,

    input logic i_tile_done, // signal FROM tile controller

    output logic o_start_tile, // send these signals TO the tile controller
    output logic o_layer_type,
    output logic [15:0] o_Cin,
    output logic [31:0] o_weight_offset,

    output logic o_done
);

    // a table that contains all the layer information
    layer_cfg_t layer_table [NUM_LAYERS]; // array of the structs
    // each entry will have info for one layer (ROM for layers):
    // DW or PW | Cin | Cout | Weight Offs. | H, W
    
    // btw, clog is ceiling log 2 = min bits to represent x - 1
    // ex: clog(4) = 2
    logic [$clog2(NUM_LAYERS)-1:0] layer_idx; // counter 
    // which layer are we currently running on 
    // if the numlayer is 4, we have to cycle 00 - 01 - 10 - 11
    
    layer_cfg_t current_layer;
    
    
    // FSM for different states of layer handling:
    typedef enum logic [1:0] {
        layer_idle,
        layer_load,
        layer_wait,
        layer_done
    } state_t;
    
    state_t state;
    
    // add all the layer information here (layer_table)
    // '{ field0, field1, field2, field3, field4, field5 }
    initial begin
    // sample
        // Depthwise layer
        layer_table[0] = '{
            layer_type: 2'd0,
            Cin:        16'd8,
            Cout:       16'd8,
            H:          16'd96,
            W:          16'd96,
            weight_offset: 32'd0 // place holder
        };
    
        // Pointwise layer
        layer_table[1] = '{
            layer_type: 2'd1,
            Cin:        16'd32,
            Cout:       16'd64,
            H:          16'd96,
            W:          16'd96,
            weight_offset: 32'd2048
        };
    end
    
    always_ff @(posedge i_clk or negedge i_nrst) begin
    if (!i_nrst) begin
        state        <= layer_idle;
        layer_idx    <= 0;
        o_start_tile <= 0;
        o_done       <= 0;
    end else begin
        case (state)

            /////////////////////////////////
            layer_idle: begin
                o_done <= 0;
                if (i_start) begin
                    layer_idx <= 0;
                    state <= layer_idle;
                end
            end

            /////////////////////////////////
            // output the layer configuration 
            layer_load: begin
                current_layer <= layer_table[layer_idx];

                o_layer_type    <= layer_table[layer_idx].layer_type[0];
                o_Cin           <= layer_table[layer_idx].Cin;
                o_weight_offset <= layer_table[layer_idx].weight_offset;

                o_start_tile <= 1; // output to the tile controller to start exec
                state <= layer_wait;
            end

            /////////////////////////////////
            layer_wait: begin
                o_start_tile <= 0; // wait for i_tile_done

                if (i_tile_done) begin
                    if (layer_idx == NUM_LAYERS-1)
                        state <= layer_done; // if done, layer done
                    else begin
                        layer_idx <= layer_idx + 1;
                        state <= layer_load; // else, go to the next layer of the model
                    end
                end
            end

            /////////////////////////////////
            layer_done: begin
                o_done <= 1;
            end

        endcase
    end
end

endmodule
