// Register File & Registers
module RegisterFile#(
    parameter ROB_WIDTH = 4
)(
    input wire  clockIn,
    input wire  resetIn,
    input wire  readyIn,
    input wire  clearIn,

    // instruction unit
    input wire  rdFlag,
    input wire  [4:0] rdAddr,
    input wire  [ROB_WIDTH-1:0] rdDest,
    input wire  [4:0] rs1Addr,
    input wire  [4:0] rs2Addr,
    output wire [31:0] rs1Value,
    output wire [ROB_WIDTH-1:0] rs1Rename,
    output wire rs1Busy,
    output wire [31:0] rs2Value,
    output wire [ROB_WIDTH-1:0] rs2Rename,
    output wire rs2Busy,

    // reorder buffer
    input wire  writeFlag,
    input wire  [ROB_WIDTH-1:0] robId,
    input wire  [4:0] writeAddr,
    input wire  [31:0] writeValue
);

reg [31:0] registers [31:0];
reg [31:0] busy;
reg [ROB_WIDTH-1:0] reorder [31:0];

// deal with rs1 & rs2
assign rs1Value = registers[rs1Addr];
assign rs1Busy= busy[rs1Addr];
assign rs1Rename = reorder[rs1Addr];
assign rs2Value = registers[rs2Addr];
assign rs2Busy = busy[rs2Addr];
assign rs2Rename = reorder[rs2Addr];

integer i;
always @(posedge clockIn) begin
    if (resetIn) begin
        for (i = 0; i < 32; i = i+1) begin
            registers[i] <= 0;
            busy[i] <= 1'b0;
            reorder[i] <= 0;
        end
    end else if (clearIn) begin
        busy <= {32{1'b0}};
    end else if (readyIn) begin
        // update registers
        if (writeFlag & (writeAddr != 0))
            registers[writeAddr] <= writeValue;
        // update reorder && busy
        if (rdFlag & (rdAddr != 0)) begin
            busy[rdAddr] <= 1'b1;
            reorder[rdAddr] <= rdDest;
            if (writeFlag && writeAddr != rdAddr && reorder[writeAddr] == robId)
                busy[writeAddr] <= 1'b0;
        end else if (writeFlag && reorder[writeAddr] == robId)
            busy[writeAddr] <= 1'b0;
    end
end

endmodule
