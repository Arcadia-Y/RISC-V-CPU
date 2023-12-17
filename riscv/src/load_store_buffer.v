// Load Store Buffer
module LoadStoreBuffer#(
    parameter ROB_WIDTH = 4,
    parameter LSB_WIDTH = 4
)(
    input wire  clockIn,
    input wire  resetIn,
    input wire  readyIn,

    // for wrong branch prediction
    input wire  clearIn,

    // instruction unit
    input wire  addFlag,
    input wire  [3:0] addOp,
    input wire  [31:0] addVj,
    input wire  [ROB_WIDTH-1:0] addQj,
    input wire  addQjBusy,
    input wire  [31:0] addVk,
    input wire  [ROB_WIDTH-1:0] addQk,
    input wire  addQkBusy,
    input wire  [31:0] addImm,
    input wire  [ROB_WIDTH-1:0] addDest,
    output wire full,

    // ALU forward input
    input wire  aluFlag,
    input wire  [31:0] aluVal,
    input wire  [ROB_WIDTH-1:0] aluDest,

    // ROB commit (for store)  
    input wire  robFLag,
    input wire  [ROB_WIDTH-1:0] robDest,

    // write results & forward (for load)
    output wire outFlag,
    output wire [31:0] outVal,
    output wire [ROB_WIDTH-1:0] outDest,

    // memory controller
    output wire memOutFlag,
    output wire [2:0] memOp,
    output wire [31:0] memAddr,
    output wire [31:0] memDataOut,
    input wire  [31:0] memDataIn,
    input wire  memOkFlag 
);

parameter LSB_SIZE = 2**LSB_WIDTH;

/*  op[3]: 0 for load, 1 for store
 *  op[2]: 0 for signed, 1 for unsigned
 *  op[1:0]: 00 for byte, 01 for half word, 11 for word
 *  Vj: rs1 for load and store
 *  Vk: rs2 for store
 */
reg [3:0] op [LSB_SIZE-1:0];
reg [LSB_SIZE-1:0] busy;
reg [LSB_SIZE-1:0] commited; // only for store
reg [31:0] Vj [LSB_SIZE-1:0];
reg [31:0] Vk [LSB_SIZE-1:0];
reg [LSB_SIZE-1:0] QjBusy;
reg [LSB_SIZE-1:0] QkBusy;
reg [ROB_WIDTH-1:0] Qj [LSB_SIZE-1:0];
reg [ROB_WIDTH-1:0] Qk [LSB_SIZE-1:0];
reg [31:0] imm [LSB_SIZE-1:0];
reg [ROB_WIDTH-1:0] dest [LSB_SIZE-1:0];
// FIFO
reg [LSB_WIDTH-1:0] head;
reg [LSB_WIDTH-1:0] tail;

reg memOutReg;
reg outFlagReg;
reg [31:0] outValReg;
reg [ROB_WIDTH-1:0] outDestReg;
reg [LSB_SIZE-1:0] lastCommit;

assign full = (tail == head) & busy[0];
assign memOutFlag = memOutReg & ~memOkFlag; // to avoid duplicate read/write
assign outFlag = outFlagReg;
assign outVal = outValReg;
assign outDest = outDestReg;
assign memOp = {op[head][3], op[head][1:0]};
assign memAddr = Vj[head] + imm[head];
assign memDataOut = Vk[head];

wire [LSB_WIDTH-1:0] nextHead = head + 1'b1;
wire [LSB_WIDTH-1:0] nextTail = tail + 1'b1;
wire headLoad = ~op[head][3];
wire headUnsigned = op[head][2];
wire [31:0] toCommit = headUnsigned ? memDataIn :
                       head[1] ? memDataIn :
                       head[0] ? {{16{memDataIn[15]}}, memDataIn[15:0]} :
                       {{24{memDataIn[7]}}, memDataIn[7:0]};

integer i;
always @(posedge clockIn) begin
    if (resetIn) begin
        busy <= 0;
        commited <= 0;
        head <= 0;
        tail <= 0;
        memOutReg <= 1'b0;
        outFlagReg <= 1'b0;
        for (i = 0; i < LSB_SIZE; i = i + 1) begin
            QjBusy[i] <= 1'b0;
            QkBusy[i] <= 1'b0;
        end
    end
    else if (clearIn & readyIn & busy[head]) begin
        for (i = 0; i < LSB_SIZE; i = i + 1)
            if (~commited[i])
                busy[i] <= 1'b0;
        if (headLoad) begin
            tail <= head;
            memOutReg <= 1'b0;
        end else begin
            tail <= lastCommit + 1'b1;
            if (memOutReg & memOkFlag) begin // store complete
                memOutReg <= 1'b0;
                busy[head] <= 1'b0;
                commited[head] <= 1'b0;
                head <= nextHead;
            end
        end
    end
    else if (readyIn) begin
        // add entry
        if (addFlag & ~full) begin
            busy[tail] <= 1'b1;
            op[tail] <= addOp;
            commited[tail] <= 1'b0;
            Vj[tail] <= addVj;
            Vk[tail] <= addVk;
            QjBusy[tail] <= addQjBusy;
            QkBusy[tail] <= addQkBusy;
            Qj[tail] <= addQj;
            Qk[tail] <= addQk;
            imm[tail] <= addImm;
            dest[tail] <= addDest;
            tail <= nextTail;
        end
        // process load/store
        if (busy[head]) begin
            if (headLoad) begin // load
                if (memOutReg & memOkFlag) begin // commit
                    outFlagReg <= 1'b1;
                    outValReg <= toCommit;
                    outDestReg <= dest[head];
                    memOutReg <= 1'b0;
                    busy[head] <= 1'b0;
                    head <= nextHead;
                end else if (~memOutReg) begin // before loading
                    memOutReg <= QjBusy[head];
                end
            end else begin // store
                if (memOutReg & memOkFlag) begin // store complete
                    memOutReg <= 1'b0;
                    busy[head] <= 1'b0;
                    commited[head] <= 1'b0;
                    head <= nextHead;
                end else if (~memOutReg & (commited[head] | 
                    (robFLag & (dest[head] == robDest)))) begin // before storing
                    memOutReg <= 1'b1;
                end
            end
        end
        // update Vj/Vk from ALU
        if (aluFlag) begin
            for (i = 0; i < LSB_SIZE; i = i + 1) begin
                if (QjBusy[i] & (Qj[i] == aluDest)) begin
                    QjBusy[i] <= 1'b0;
                    Vj[i] <= aluVal;
                end
                if (QkBusy[i] & (Qk[i] == aluDest)) begin
                    QkBusy[i] <= 1'b0;
                    Qk[i] <= aluVal;
                end
            end
        end
        // update Vj/Vk from lsb
        if (outFlag) begin
            outFlagReg <= 1'b0; // clear outFlag
            for (i = 0; i < LSB_SIZE; i = i + 1) begin
                if (QjBusy[i] & (Qj[i] == outDest)) begin
                    QjBusy[i] <= 1'b0;
                    Vj[i] <= outVal;
                end
                if (QkBusy[i] & (Qk[i] == outDest)) begin
                    QkBusy[i] <= 1'b0;
                    Qk[i] <= outVal;
                end
            end
        end
        // update commited from rob
        if (robFLag) begin
            for (i = 0; i < LSB_SIZE; i = i + 1)
                if (busy[i] & (dest[i] == robDest) & ~commited[i]) begin
                    commited[i] <= 1'b1;
                    lastCommit <= i;
                end
        end
    end
end

endmodule