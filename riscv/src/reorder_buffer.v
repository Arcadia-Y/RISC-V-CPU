// Reorder Buffer
module ReorderBuffer#(
    parameter ROB_WIDTH = 4
)(
    input wire  clockIn,
    input wire  resetIn,
    input wire  readyIn,

    // for wrong branch prediction
    output wire clear,

    // instruction unit
    input wire  addFlag,
    input wire  [1:0] addType,
    input wire  [4:0] addDest,
    input wire  addJump, // predicted jump signal
    input wire  [31:0] addPC, // pc to set for wrong prediction
    input wire  [31:0] addInsAddr, // the instruction address
    input wire  addValueFlag, // for lui, auipc
    input wire  [31:0] addValue, 
    output wire [ROB_WIDTH-1:0] freeId,
    output wire full,
    output wire [31:0] setPCVal,

    // rs1 & rs2 (instruction unit)
    input wire  [ROB_WIDTH-1:0] rs1Id,
    input wire  [ROB_WIDTH-1:0] rs2Id,
    output wire rs1Busy,
    output wire [31:0] rs1Val,
    output wire rs2Busy,
    output wire [31:0] rs2Val,

    // predictor
    output wire predictFlag,
    output wire [31:0] predictAddr, // the instruction address
    output wire predictVal, // update value

    // register file
    output wire rfFlag,
    output wire [ROB_WIDTH-1:0] rfRobId,
    output wire [4:0] rfDest,
    output wire [31:0] rfValue,

    // reservation station
    input wire  rsFlag,
    input wire  [ROB_WIDTH-1:0] rsId,
    input wire  [31:0] rsValue,

    // LSB
    input wire  loadFlag,
    input wire  [ROB_WIDTH-1:0] loadId,
    input wire  [31:0] loadValue,
    output wire storeFlag,
    output wire [ROB_WIDTH-1:0] storeId,
    output wire [ROB_WIDTH-1:0] headId
);

parameter ROB_SIZE = 2**ROB_WIDTH;
reg [ROB_SIZE-1:0] busy;
reg [ROB_SIZE-1:0] jump;
reg [ROB_SIZE-1:0] ready;
parameter BRANCH = 2'b10;
parameter STORE = 2'b11;
parameter OTHER = 2'b00;
reg [1:0] insType [ROB_SIZE-1:0];
reg [4:0] dest [ROB_SIZE-1:0];
reg [31:0] value [ROB_SIZE-1:0];
reg [31:0] PC [ROB_SIZE-1:0];
reg [31:0] insAddr [ROB_SIZE-1:0];
reg [ROB_WIDTH-1:0] head;
reg [ROB_WIDTH-1:0] tail;

reg predictReg;
reg rfReg;
reg storeReg;
reg [ROB_WIDTH-1:0] commitId;
reg [31:0] commitAddr;
reg [4:0] commitDest;
reg [31:0] commitVal;
reg clearReg;
reg [31:0] setPCReg;

assign clear = clearReg;
assign freeId = tail;
assign full = busy == {ROB_SIZE{1'b1}};
assign rs1Busy = ~ready[rs1Id];
assign rs1Val = value[rs1Id];
assign rs2Busy = ~ready[rs2Id];
assign rs2Val = value[rs2Id];

assign setPCVal = setPCReg;
assign predictFlag = predictReg;
assign predictAddr = commitAddr;
assign predictVal = commitVal[0];
assign rfFlag = rfReg;
assign rfRobId = commitId;
assign rfDest = commitDest;
assign rfValue = commitVal;
assign storeFlag = storeReg;
assign storeId = commitId;
assign headId = head;

wire hasFree = ~full;
wire wrongPredict = value[head][0] ^ jump[head];

always @(posedge clockIn) begin
    if (resetIn | (clear & readyIn)) begin
        busy <= 0;
        head <= 0;
        tail <= 0;
        predictReg <= 0;
        rfReg <= 0;
        storeReg <= 0;
        commitId <= 0;
        commitAddr <= 0;
        commitDest <= 0;
        commitVal <= 0;
        clearReg <= 0;
        setPCReg <= 0;
    end else if (readyIn) begin
        // add entry
        if (addFlag & hasFree) begin
            busy[tail] <= 1;
            insType[tail] <= addType;
            dest[tail] <= addDest;
            jump[tail] <= addJump;
            PC[tail] <= addPC;
            insAddr[tail] <= addInsAddr;
            ready[tail] <= addValueFlag;
            value[tail] <= addValue;
            tail <= tail + 1'b1;
        end
        // update from RS
        if (rsFlag) begin
            value[rsId] <= rsValue;
            ready[rsId] <= 1;
        end
        // update from LSB
        if (loadFlag) begin
            value[loadId] <= loadValue;
            ready[loadId] <= 1;
        end
        // commit
        if (busy[head] & ready[head]) begin
            head <= head + 1'b1;
            busy[head] <= 0;
            commitAddr <= insAddr[head];
            commitDest <= dest[head];
            commitId <= head;
            case (insType[head])
            BRANCH: begin
                clearReg <= wrongPredict;
                setPCReg <= PC[head];
                predictReg <= 1;
                commitVal <= value[head];
                rfReg <= 0;
                storeReg <= 0;
            end 
            STORE: begin
                clearReg <= 0;
                predictReg <= 0;
                rfReg <= 0;
                storeReg <= 1;
            end
            default: begin // others
                clearReg <= 0;
                predictReg <= 0;
                rfReg <= 1;
                commitVal <= value[head];
                storeReg <= 0;
            end   
            endcase
        end else begin
            clearReg <= 0;
            predictReg <= 0;
            rfReg <= 0;
            storeReg <= 0;
        end
    end
end

endmodule