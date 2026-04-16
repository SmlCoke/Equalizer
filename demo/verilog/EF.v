
module EF
#(
    parameter TAP_N     = 5, // can change, student self-define
    parameter DI_IL_W   = 2, // can change, student self-define
    parameter DI_FL_W   = 4, // can change, student self-define
    parameter DI_W      = DI_IL_W + DI_FL_W + 1
    parameter C_IL_W    = 1, // can change, student self-define
    parameter C_FL_W    = 4, // can change, student self-define
    parameter C_W       = C_IL_W + C_FL_W + 1,
    parameter DO_IL_W   = 2, // can change, student self-define
    parameter DO_FL_W   = 4, // can change, student self-define
    parameter DO_W      = DO_IL_W + DO_FL_W + 1
)
(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 valid_i,
    input  wire [DI_W-1:0]      data_i,
    input  wire [TAP_N*C_W-1:0] coeff_i,
    output reg                  valid_o, // wire or reg, student self-define
    output reg  [DO_W-1:0]      data_o   // wire or reg, student self-define
);

// here to begin your design

endmodule