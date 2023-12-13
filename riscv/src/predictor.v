// 2-bit Branch Predictor
module BranchPredictor#(
    parameter TABLE_WIDTH = 6,
    parameter TABLE_SIZE = 2 ** TABLE_WIDTH
)(
    input wire  resetIn,
    input wire  clockIn,
    input wire  readyIn,
    
    // instruction unit
    input wire [31:0] predictAddr,
    output wire jump,

    // ROB
    input wire  updateFlag,
    input wire [31:0] updateAddr,
    input wire  updateVal
);

reg [TABLE_WIDTH-1:0] predictPos;
reg [1:0] historyTable [TABLE_SIZE-1:0];
wire [TABLE_WIDTH-1:0] updatePos = updateAddr [TABLE_WIDTH+1:2];
assign jump = historyTable[predictPos][1];

integer i;
always@(posedge clockIn) begin
    if (resetIn) begin
        for (i = 0; i < TABLE_SIZE; i = i + 1)
            historyTable[i] <= 2'b10;
        predictPos <= 0;
    end else if (readyIn) begin
        if (updateFlag) begin
            predictPos <= predictAddr[TABLE_WIDTH+1:2];
            case (historyTable[updatePos])
                2'b00: historyTable[updatePos] <= updateVal ? 2'b01 : 2'b00;
                2'b01: historyTable[updatePos] <= updateVal ? 2'b10 : 2'b00;
                2'b10: historyTable[updatePos] <= updateVal ? 2'b11 : 2'b01;
                2'b11: historyTable[updatePos] <= updateVal ? 2'b11 : 2'b10;
            endcase
        end
    end
end

endmodule
