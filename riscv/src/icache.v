// Instruction Cache
module ICache#(
    parameter BLOCK_OFFSET = 2,
    parameter CACHE_WIDTH = 8,
    parameter TAG_WIDTH = 7
)(
    input wire  clockIn,
    input wire  resetIn,
    input wire  readyIn,

    // instruction unit
    input wire  readFlag,
    input wire  [31:0] addrIn,
    output wire hit,
    output wire [31:0] dataOut,

    // memory controller
    input wire  validIn,
    input wire  [31:0] dataIn,
    output wire memFlag,
    output wire [31:0] addrOut
);

parameter CACHE_SIZE = 2**CACHE_WIDTH;
//  valid bit | tag | data
//      1        7     32
reg [32+TAG_WIDTH:0] block [CACHE_SIZE-1:0];
reg memFlagReg; // also as state signal
reg [31:0] addrOutReg;

wire [CACHE_WIDTH-1:0] index = addrIn[CACHE_WIDTH+1:2];
wire [TAG_WIDTH-1:0] tag = addrIn[CACHE_WIDTH + TAG_WIDTH + 1:CACHE_WIDTH+2];
wire [32+TAG_WIDTH:0] selected = block[index];
assign hit = selected[32+TAG_WIDTH] & tag == selected[31+TAG_WIDTH:32];
assign dataOut = selected[31:0];
assign memFlag = memFlagReg;
assign addrOut = addrOutReg;
wire outIndex = addrOut[CACHE_WIDTH+1:2];
wire outTag = addrOut[CACHE_WIDTH + TAG_WIDTH + 1:CACHE_WIDTH+2];

integer i;
always @(posedge clockIn) begin
    if (resetIn) begin
        memFlagReg <= 0;
        addrOutReg <= 0;
        for (i = 0; i < CACHE_SIZE; i = i + 1)
            block[i][32+TAG_WIDTH] <= 1'b0;
    end 
    else if (readyIn) begin
        if (memFlag) begin
            if (validIn) begin
                block[outIndex][31:0] <= dataIn;
                block[outIndex][31+TAG_WIDTH:32] <= outTag;
                block[outIndex][32+TAG_WIDTH] <= 1'b1;
                memFlagReg <= 0;
            end
        end 
        else if (readFlag & !hit) begin
            block[index][32+TAG_WIDTH] <= 1'b0;
            addrOutReg <= addrIn;
            memFlagReg <= 1'b1;
        end
    end
end

endmodule