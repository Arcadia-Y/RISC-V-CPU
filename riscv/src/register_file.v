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

reg [31:0] rs1ValReg;
reg rs1BusyReg;
reg [ROB_WIDTH-1:0] rs1RenameReg;
reg [31:0] rs2ValReg;
reg rs2BusyReg;
reg [ROB_WIDTH-1:0] rs2RenameReg;

// deal with rs1 & rs2
assign rs1Value = rs1ValReg;
assign rs1Busy = rs1BusyReg;
assign rs1Rename = rs1RenameReg;
assign rs2Value = rs2ValReg;
assign rs2Busy = rs2BusyReg;
assign rs2Rename = rs2RenameReg;

`ifdef DEBUG
integer fileHandle;
initial begin
    fileHandle = $fopen("reg.txt");
end
`endif

integer i;
always @(posedge clockIn) begin
    if (resetIn) begin
        for (i = 0; i < 32; i = i+1) begin
            registers[i] <= 0;
            busy[i] <= 1'b0;
            reorder[i] <= 0;
        end
        rs1ValReg <= 0;
        rs1BusyReg <= 0;
        rs1RenameReg <= 0;
        rs2ValReg <= 0;
        rs2BusyReg <= 0;
        rs2RenameReg <= 0;
    end else if (clearIn & readyIn) begin
        busy <= {32{1'b0}};
    end else if (readyIn) begin
        rs1ValReg <= registers[rs1Addr];
        rs1BusyReg <= busy[rs1Addr];
        rs1RenameReg <= reorder[rs1Addr];
        rs2ValReg <= registers[rs2Addr];
        rs2BusyReg <= busy[rs2Addr];
        rs2RenameReg <= reorder[rs2Addr];
        // update registers
        if (writeFlag & (writeAddr != 0)) begin
            registers[writeAddr] <= writeValue;
            `ifdef DEBUG
            $fdisplay(fileHandle, "reg %d <- %d", writeAddr, writeValue);
            `endif
            if (rs1Addr == writeAddr)
                rs1ValReg <= writeValue;
            if (rs2Addr == writeAddr)
                rs2ValReg <= writeValue;
        end 
        // update reorder && busy
        if (rdFlag & (rdAddr != 0)) begin
            busy[rdAddr] <= 1'b1;
            reorder[rdAddr] <= rdDest;
            if (rs1Addr == rdAddr) begin
                rs1BusyReg <= 1'b1;
                rs1RenameReg <= rdDest;
            end
            if (rs2Addr == rdAddr) begin
                rs2BusyReg <= 1'b1;
                rs2RenameReg <= rdDest;
            end
            if (writeFlag && writeAddr != rdAddr && reorder[writeAddr] == robId) begin
                busy[writeAddr] <= 1'b0;
                if (rs1Addr == writeAddr)
                    rs1BusyReg <= 1'b0;
                if (rs2Addr == writeAddr)
                    rs2BusyReg <= 1'b0;
            end
        end else if (writeFlag && reorder[writeAddr] == robId) begin
            busy[writeAddr] <= 1'b0;
            if (rs1Addr == writeAddr)
                rs1BusyReg <= 1'b0;
            if (rs2Addr == writeAddr)
                rs2BusyReg <= 1'b0;
        end
    end
end

endmodule
