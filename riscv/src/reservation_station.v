// Reservation Station & ALU
module ReservationStation#(
    parameter ROB_WIDTH = 4,
    parameter RS_WIDTH = 4
)(
    input wire  clockIn,
    input wire  resetIn,
    input wire  readyIn,

    // instruction unit
    input wire  addFlag,
    input wire  [3:0] addOp,
    input wire  [31:0] addVj,
    input wire  [ROB_WIDTH-1:0] addQj,
    input wire  addQjBusy,
    input wire  [31:0] addVk,
    input wire  [ROB_WIDTH-1:0] addQk,
    input wire  addQkBusy,
    input wire  [ROB_WIDTH-1:0] addDest,
    output wire full,

    // LSB forward input
    input wire  lsbFlag,
    input wire  [31:0] lsbVal,
    input wire  [ROB_WIDTH-1:0] lsbDest,

    // write results & forward
    output wire outFlag,
    output wire [31:0] outVal,
    output wire [ROB_WIDTH-1:0] outDest
);

parameter RS_SIZE = 2**RS_WIDTH;
parameter ADD = 4'b0000;
parameter SUB = 4'b0001;
parameter SLL = 4'b0010;
parameter XOR = 4'b0011;
parameter SRL = 4'b0100;
parameter SRA = 4'b0101;
parameter OR  = 4'b0110;
parameter AND = 4'b0111;
parameter EQ  = 4'b1000;
parameter NE  = 4'b1001;
parameter LT  = 4'b1010;
parameter GE  = 4'b1011;
parameter LTU = 4'b1100;
parameter GEU = 4'b1101;

// ALU Logic
wire [31:0] rs1;
wire [31:0] rs2;
wire [31:0] aluRes[13:0];
assign aluRes[ADD] = rs1 + rs2;
assign aluRes[SUB] = rs1 - rs2;
assign aluRes[SLL] = rs1 << rs2;
assign aluRes[XOR] = rs1 ^ rs2;
assign aluRes[SRL] = rs1 >> rs2;
assign aluRes[SRA] = rs1 >>> rs2;
assign aluRes[OR]  = rs1 | rs2;
assign aluRes[AND] = rs1 & rs2;
assign aluRes[EQ]  = rs1 == rs2 ? 1 : 0;
assign aluRes[NE]  = rs1 != rs2 ? 1 : 0;
assign aluRes[LT]  = $signed(rs1) < $signed(rs2) ? 1 : 0;
assign aluRes[GE]  = $signed(rs1) >= $signed(rs2) ? 1 : 0;
assign aluRes[LTU]  = rs1 < rs2 ? 1 : 0;
assign aluRes[GEU]  = rs1 >= rs2 ? 1 : 0;

// RS Logic
reg [RS_SIZE-1:0] busy;
reg [3:0] op [RS_SIZE-1:0];
reg [RS_SIZE-1:0] QjBusy;
reg [RS_SIZE-1:0] QkBusy;
reg [ROB_WIDTH-1:0] Qj [RS_SIZE-1:0];
reg [ROB_WIDTH-1:0] Qk [RS_SIZE-1:0];
reg [31:0] Vj [RS_SIZE-1:0];
reg [31:0] Vk [RS_SIZE-1:0];
reg [ROB_WIDTH-1:0] dest [RS_SIZE-1:0];

wire [RS_WIDTH-1:0] freeSlot; 
wire [RS_WIDTH-1:0] calcSlot;
assign full = (busy == {RS_SIZE{1'b1}});
assign freeSlot = ~busy[0] ? 0 :
                  ~busy[1] ? 1 :
                  ~busy[2] ? 2 :
                  ~busy[3] ? 3 :
                  ~busy[4] ? 4 :
                  ~busy[5] ? 5 :
                  ~busy[6] ? 6 :
                  ~busy[7] ? 7 :
                  ~busy[8] ? 8 :
                  ~busy[9] ? 9 :
                  ~busy[10] ? 10 :
                  ~busy[11] ? 11 :
                  ~busy[12] ? 12 :
                  ~busy[13] ? 13 :
                  ~busy[14] ? 14 :
                  15;
wire [RS_WIDTH-1:0] ready = ~(QjBusy | QkBusy) & busy;
assign calcSlot = ready[0] ? 0 :
                  ready[1] ? 1 :
                  ready[2] ? 2 :
                  ready[3] ? 3 :
                  ready[4] ? 4 :
                  ready[5] ? 5 :
                  ready[6] ? 6 :
                  ready[7] ? 7 :
                  ready[8] ? 8 :
                  ready[9] ? 9 :
                  ready[10] ? 10 :
                  ready[11] ? 11 :
                  ready[12] ? 12 :
                  ready[13] ? 13 :
                  ready[14] ? 14 :
                  15;
assign rs1 = Vj[calcSlot];
assign rs2 = Vk[calcSlot];
wire [3:0] calcOp = op[calcSlot];
wire hasCalc = ready != 0;

// calculation result to send out
reg outFlagReg;
reg [31:0] outValReg;
reg [ROB_WIDTH-1:0] outDestReg;
assign outFlag = outFlagReg;
assign outVal = outValReg;
assign outDest = outDestReg;

integer i;
always @(posedge clockIn) begin
    if (resetIn) begin
        busy <= 0;
        outFlagReg <= 1'b0;
    end
    else if (readyIn) begin
        // add entry
        if (addFlag) begin
            busy[freeSlot] <= 1'b1;
            op[freeSlot] <= addOp;
            QjBusy[freeSlot] <= addQjBusy;
            QkBusy[freeSlot] <= addQkBusy;
            Vj[freeSlot] <= addVj;
            Vk[freeSlot] <= addVk;
            Qj[freeSlot] <= addQj;
            Qk[freeSlot] <= addQk;
            dest[freeSlot] <= addDest;
        end
        // calculate
        outFlagReg <= hasCalc;
        outValReg <= aluRes[calcSlot];
        outDestReg <= dest[calcSlot];
        if (hasCalc)
            busy[calcSlot] <= 1'b0;
        // update Vj & Vk from lsb
        if (lsbFlag)
            for (i = 0; i < RS_SIZE; i = i + 1) 
                if (busy[i]) begin
                    if (QjBusy[i] & (Qj[i] == lsbDest)) begin
                        QjBusy[i] <= 1'b0;
                        Vj[i] <= lsbVal;
                    end
                    if (QkBusy[i] & (Qk[i] == lsbDest)) begin
                        QkBusy[i] <= 1'b0;
                        Vk[i] <= lsbVal;
                    end
                end
        // update Vj & Vk from alu
        if (outFlag)
            for (i = 0; i < RS_SIZE; i = i + 1)
                if (busy[i]) begin
                    if (QjBusy[i] & (Qj[i] == outDest)) begin
                        QjBusy[i] <= 1'b0;
                        Vj[i] <= outVal;
                    end
                    if (QkBusy[i] & (Qk[i] == outDest)) begin
                        QkBusy[i] <= 1'b0;
                        Vk[i] <= outVal;
                    end
                end
    end
end

endmodule
