// Instruction Unit & PC
module InstructionUnit#(
    parameter ROB_WIDTH = 4
)(
    input wire  clockIn,
    input wire  resetIn,
    input wire  readyIn,

    // icache
    output wire [31:0] fetchOut,
    input wire  hit,
    input wire  [31:0] icacheIn,

    // register file
    output reg  rdFlag,
    output wire [4:0] rdAddr,
    output wire [ROB_WIDTH-1:0] rdDest,
    output wire [4:0] rs1Addr,
    output wire [4:0] rs2Addr,
    input wire  [31:0] rfRs1,
    input wire  [ROB_WIDTH-1:0] rfRs1Id,
    input wire  rfRs1Busy,
    input wire  [31:0] rfRs2,
    input wire  [ROB_WIDTH-1:0] rfRs2Id,
    input wire  rfRs2Busy,

    // predictor
    output wire [31:0] insAddrOut,
    input wire  predictJump,

    // reorder buffer
    output reg  robFlag,
    output reg  [1:0] robType,
    output wire robJump,
    output reg  [31:0] robPC,
    output reg  robValueFlag,
    output reg  [31:0] robValue,
    input wire  [ROB_WIDTH-1:0] robFree,
    input wire  robFull,
    input wire  clearIn,
    input wire  [31:0] setPCVal,
    output wire [ROB_WIDTH-1:0] robRs1Id,
    output wire [ROB_WIDTH-1:0] robRs2Id,
    input wire  robRs1Busy,
    input wire  robRs2Busy,
    input wire  [31:0] robRs1Val,
    input wire  [31:0] robRs2Val,

    // reservation station
    output reg  rsFlag,
    output reg  [3:0] rsOp,
    output wire [31:0] rs1Out,
    output wire [31:0] rs2Out,
    output wire rs1Busy,
    output wire rs2Busy,
    output wire [ROB_WIDTH-1:0] rs1IdOut,
    output wire [ROB_WIDTH-1:0] rs2IdOut,
    output wire [ROB_WIDTH-1:0] outDest,
    input wire  rsFull,

    // load store buffer
    output reg  lsbFlag,
    output reg  [3:0] lsbOp,
    output reg  [31:0] lsbImm,
    input wire  lsbFull
);

reg [31:0] fetchAddr;
reg [31:0] insReg;
reg [31:0] PC;
reg insValid;

// decode and issue
reg stall;
reg needJump;
reg [31:0] jumpPCVal;

wire [6:0] opcode = insReg[6:0];
wire [4:0] rd = insReg[11:7];
wire [2:0] funct3 = insReg[14:12];
wire [4:0] rs1 = insReg[19:15];
wire [4:0] rs2 = insReg[24:20];
wire [6:0] funct7 = insReg[31:25];
wire [31:0] imm12 = {{20{insReg[31]}}, insReg[31:20]};
wire [31:0] immB = {{20{insReg[31]}}, insReg[7], insReg[30:25], insReg[11:8], 1'b0};
wire [31:0] immS = {{20{insReg[31]}}, insReg[31:25], insReg[11:7]};

assign rdAddr = rd;
assign rdDest = robFree;
assign rs1Addr = insValid & stall ? rs1 : 
                   hit ? icacheIn[19:15] : 0;
assign rs2Addr = insValid & stall ? rs2 : 
                   hit ? icacheIn[24:20] : 0;
assign insAddrOut = PC;
assign robJump = predictJump;
assign robRs1Id = rfRs1Id;
assign robRs2Id = rfRs2Id;
assign rs1Out = rfRs1Busy ? robRs1Val : rfRs1;
assign rs2Out = opcode == 7'b0010011 ? imm12 :
                rfRs2Busy ? robRs2Val : rfRs2;
assign rs1Busy = ~rfRs1Busy ? 0 : robRs1Busy;
assign rs2Busy = opcode == 7'b0010011 ? 0 :
                 ~rfRs2Busy ? 0 : robRs2Busy;
assign rs1IdOut = rfRs1Id;
assign rs2IdOut = rfRs2Id;
assign outDest = robFree;

always@(*) begin
    rdFlag = 0;
    robFlag = 0;
    robType = 0;
    robPC = 0;
    robValueFlag = 0;
    robValue = 0;
    rsFlag = 0;
    rsOp = 0;
    lsbFlag = 0;
    lsbOp = 0;
    lsbImm = 0;
    stall = 0;
    needJump = 0;
    jumpPCVal = 0;
    if (insValid & ~robFull) begin
        case (opcode)
        7'b0110111: begin // lui
            robFlag = 1;
            rdFlag = 1;
            robValueFlag = 1;
            robValue = insReg[31:12] << 12;
        end
        7'b0010111: begin // auipc
            robFlag = 1;
            rdFlag = 1;
            robValueFlag = 1;
            robValue = PC + (insReg[31:12] << 12);
        end
        7'b1101111: begin // jal
            robFlag = 1;
            rdFlag = 1;
            needJump = 1;
            jumpPCVal = PC + {{12{insReg[31]}}, insReg[19:12], insReg[20], insReg[30:21], 1'b0};        
            robValueFlag = 1;
            robValue = PC + 4;
        end
        7'b1100111: begin // jalr
            if (rs1Busy) begin
                stall = 1;
            end else begin
                robFlag = 1;
                rdFlag = 1;
                needJump = 1;
                jumpPCVal = rs1Out + imm12;
                robValueFlag = 1;
                robValue = PC + 4;
            end
        end
        7'b1100011: begin // BRANCH
            if (rsFull) begin
                stall = 1;
            end else begin
                robFlag = 1;
                robType = 2'b10;
                if (predictJump) begin
                    needJump = 1;
                    jumpPCVal = PC + immB;
                    robPC = PC + 4;
                end else begin
                    robPC = PC + immB;
                end
                rsFlag = 1;
                case (funct3)
                    3'b000: rsOp = 4'b1000; // beq 
                    3'b001: rsOp = 4'b1001; // bne
                    3'b100: rsOp = 4'b1010; // blt
                    3'b101: rsOp = 4'b1011; // bge
                    3'b110: rsOp = 4'b1100; // bltu
                    3'b111: rsOp = 4'b1101; // bgeu  
                endcase
            end
        end
        7'b0000011: begin // LOAD
            if (lsbFull) begin
                stall = 1;
            end else begin
                robFlag = 1;
                rdFlag = 1;
                lsbFlag = 1;
                lsbImm = imm12;
                lsbOp[3] = 1'b0;
                case (funct3) 
                    3'b000: lsbOp[2:0] = 3'b000; // lb
                    3'b001: lsbOp[2:0] = 3'b001; // lh
                    3'b010: lsbOp[2:0] = 3'b011; // lw
                    3'b100: lsbOp[2:0] = 3'b100; // lbu
                    3'b101: lsbOp[2:0] = 3'b101; // lhu
                endcase
            end
        end
        7'b0100011: begin // STORE
            if (lsbFull) begin
                stall = 1;
            end else begin
                robFlag = 1;
                robType = 2'b11;
                robValueFlag = 1;
                lsbFlag = 1;
                lsbImm = {{20{insReg[31]}}, insReg[31:25], insReg[11:7]};
                lsbOp[3:2] = 2'b10;
                case (funct3)
                    3'b000: lsbOp[1:0] = 2'b00; // sb
                    3'b001: lsbOp[1:0] = 2'b01; // sh
                    3'b010: lsbOp[1:0] = 2'b11; // sw
                endcase
            end
        end
        7'b0010011: begin // I
            if (rsFull) begin
                stall = 1;
            end else begin
                robFlag = 1;
                rdFlag = 1;
                rsFlag = 1;
                case (funct3)
                    3'b000: rsOp = 4'b0000; // addi
                    3'b010: rsOp = 4'b1010; // slti
                    3'b011: rsOp = 4'b1100; // sltiu
                    3'b100: rsOp = 4'b0011; // xori
                    3'b110: rsOp = 4'b0110; // ori
                    3'b111: rsOp = 4'b0111; // andi
                    3'b001: rsOp = 4'b0010; // slli
                    3'b101: rsOp = insReg[30] ? 4'b0101 : 4'b0100; // srli/srai 
                endcase
            end
        end
        7'b0110011: begin // R
            if (rsFull) begin
                stall = 1;
            end else begin
                robFlag = 1;
                rdFlag = 1;
                rsFlag = 1;
                case (funct3)
                    3'b000: rsOp = insReg[30] ? 4'b0001 : 4'b0000; // add/sub
                    3'b010: rsOp = 4'b1010; // slt
                    3'b011: rsOp = 4'b1100; // sltu
                    3'b100: rsOp = 4'b0011; // xor
                    3'b110: rsOp = 4'b0110; // or
                    3'b111: rsOp = 4'b0111; // and
                    3'b001: rsOp = 4'b0010; // sll
                    3'b101: rsOp = insReg[30] ? 4'b0101 : 4'b0100; // srl/sra
                endcase
            end
        end
        endcase
    end else begin
        stall = 1;
    end
end

// ifetch
assign fetchOut = fetchAddr;
always @(posedge clockIn) begin
    if (resetIn) begin
        fetchAddr <= 0;
        PC <= 0;
        insReg <= 0;
        insValid <= 0;
    end else if (clearIn & readyIn) begin
        fetchAddr <= setPCVal;
        PC <= setPCVal;
        insReg <= 0;
        insValid <= 0;
    end else if (readyIn) begin
        if (insValid & needJump) begin
            fetchAddr <= jumpPCVal;
            insValid <= 0;
        end else if (insValid & stall) begin
            insValid <= 1;
        end else if (hit) begin
            PC <= fetchAddr;
            insReg <= icacheIn;
            insValid <= 1;
            fetchAddr <= fetchAddr + 4;
        end else begin
            insValid <= 0;
        end
    end
end

endmodule