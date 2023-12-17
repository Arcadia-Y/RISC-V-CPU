// RISCV32I CPU top module
// port modification allowed for debugging purposes

module cpu(
  input  wire                 clk_in,			// system clock signal
  input  wire                 rst_in,			// reset signal
	input  wire					        rdy_in,			// ready signal, pause cpu when low

  input  wire [ 7:0]          mem_din,		// data input bus
  output wire [ 7:0]          mem_dout,		// data output bus
  output wire [31:0]          mem_a,			// address bus (only 17:0 is used)
  output wire                 mem_wr,			// write/read signal (1 for write)
	
	input  wire                 io_buffer_full, // 1 if uart buffer is full
	
	output wire [31:0]			dbgreg_dout		// cpu register output (debugging demo)
);

// implementation goes here

// Specifications:
// - Pause cpu(freeze pc, registers, etc.) when rdy_in is low
// - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)
// - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
// - I/O port is mapped to address higher than 0x30000 (mem_a[17:16]==2'b11)
// - 0x30000 read: read a byte from input
// - 0x30000 write: write a byte to output (write 0x00 is ignored)
// - 0x30004 read: read clocks passed since cpu starts (in dword, 4 bytes)
// - 0x30004 write: indicates program stop (will output '\0' through uart tx)

parameter ROB_WIDTH = 4;
parameter LSB_WIDTH = 4;
parameter RS_WIDTH = 4;

// instruction unit
wire [31:0] iuFetchOut;
wire iuRdFlag;
wire [4:0] iuRdAddr;
wire [ROB_WIDTH-1:0] iuRdDest;
wire [4:0] iuRs1Addr;
wire [4:0] iuRs2Addr;
wire [31:0] iuInsAddr;
wire iuRobFlag;
wire [1:0] iuRobType;
wire iuRobJump;
wire [31:0] iuRobPC;
wire iuRobValueFlag;
wire [31:0] iuRobValue;
wire [ROB_WIDTH-1:0] iuRobRs1Id;
wire [ROB_WIDTH-1:0] iuRobRs2Id;
wire iuRsFlag;
wire [3:0] iuRsOp;
wire [31:0] iuRs1;
wire [31:0] iuRs2;
wire iuRs1Busy;
wire iuRs2Busy;
wire [ROB_WIDTH-1:0] iuRs1Id;
wire [ROB_WIDTH-1:0] iuRs2Id;
wire [ROB_WIDTH-1:0] iuOutDest;
wire iuLsbFlag;
wire [3:0] iuLsbOp;
wire [31:0] iuLsbImm;

// reorder buffer
wire clear;
wire [ROB_WIDTH-1:0] robFreeId;
wire robFull;
wire [31:0] robSetPCVal;
wire robRs1Busy;
wire robRs2Busy;
wire [31:0] robRs1Val;
wire [31:0] robRs2Val;
wire robPredictFlag;
wire [31:0] robPredictAddr;
wire robPredictVal;
wire robRfFlag;
wire [ROB_WIDTH-1:0] robRfId;
wire [4:0] robRfDest;
wire [31:0] robRfVal;
wire robStoreFlag;
wire [ROB_WIDTH-1:0] robStoreId;

// predictor
wire predictJump;

// register file
wire [31:0] rfRs1Val;
wire [31:0] rfRs2Val;
wire [ROB_WIDTH-1:0] rfRs1Rename;
wire [ROB_WIDTH-1:0] rfRs2Rename;
wire rfRs1Busy;
wire rfRs2Busy;

// icache
wire icacheHit;
wire [31:0] icacheData;
wire icacheMemFlag;
wire [31:0] icacheAddr;

// memory controller
wire [31:0] memData;
wire memIcacheOk;
wire memLsbOk;

// load store buffer
wire lsbFull;
wire lsbOutFlag;
wire [31:0] lsbOutVal;
wire [ROB_WIDTH-1:0] lsbOutDest;
wire lsbMemFlag;
wire [2:0] lsbMemOp;
wire [31:0] lsbMemAddr;
wire [31:0] lsbMemData;

// reservation station
wire rsReset = rst_in | clear;
wire rsFull;
wire rsOutFlag;
wire [31:0] rsOutVal;
wire [ROB_WIDTH-1:0] rsOutDest;

InstructionUnit#(
  .ROB_WIDTH(ROB_WIDTH)
) instructionUnit(
  .clockIn(clk_in),
  .resetIn(rst_in),
  .readyIn(rdy_in),

  .fetchOut(iuFetchOut),
  .hit(icacheHit),
  .icacheIn(icacheData),

  .rdFlag(iuRdFlag),
  .rdAddr(iuRdAddr),
  .rdDest(iuRdDest),
  .rs1Addr(iuRs1Addr),
  .rs2Addr(iuRs2Addr),
  .rfRs1(rfRs1Val),
  .rfRs1Id(rfRs1Rename),
  .rfRs1Busy(rfRs1Busy),
  .rfRs2(rfRs2Val),
  .rfRs2Id(rfRs2Rename),
  .rfRs2Busy(rfRs2Busy),

  .insAddrOut(iuInsAddr),
  .predictJump(predictJump),

  .robFlag(iuRobFlag),
  .robType(iuRobType),
  .robJump(iuRobJump),
  .robPC(iuRobPC),
  .robValueFlag(iuRobValueFlag),
  .robValue(iuRobValue),
  .robFree(robFreeId),
  .robFull(robFull),
  .clearIn(clear),
  .setPCVal(robSetPCVal),
  .robRs1Id(iuRobRs1Id),
  .robRs2Id(iuRobRs2Id),
  .robRs1Busy(robRs1Busy),
  .robRs2Busy(robRs2Busy),
  .robRs1Val(robRs1Val),
  .robRs2Val(robRs2Val),

  .rsFlag(iuRsFlag),
  .rsOp(iuRsOp),
  .rs1Out(iuRs1),
  .rs2Out(iuRs2),
  .rs1Busy(iuRs1Busy),
  .rs2Busy(iuRs2Busy),
  .rs1IdOut(iuRs1Id),
  .rs2IdOut(iuRs2Id),
  .outDest(iuOutDest),
  .rsFull(rsFull),

  .lsbFlag(iuLsbFlag),
  .lsbOp(iuLsbOp),
  .lsbImm(iuLsbImm),
  .lsbFull(lsbFull)
);

ReorderBuffer#(
  .ROB_WIDTH(ROB_WIDTH)
) reorderBuffer(
  .clockIn(clk_in),
  .resetIn(rst_in),
  .readyIn(rdy_in),
  .clear(clear),

  .addFlag(iuRobFlag),
  .addType(iuRobType),
  .addDest(iuRdAddr),
  .addJump(iuRobJump),
  .addPC(iuRobPC),
  .addInsAddr(iuInsAddr),
  .addValueFlag(iuRobValueFlag),
  .addValue(iuRobValue),
  .freeId(robFreeId),
  .full(robFull),
  .setPCVal(robSetPCVal),

  .rs1Id(iuRobRs1Id),
  .rs2Id(iuRobRs2Id),
  .rs1Busy(robRs1Busy),
  .rs1Val(robRs1Val),
  .rs2Busy(robRs2Busy),
  .rs2Val(robRs2Val),

  .predictFlag(robPredictFlag),
  .predictAddr(robPredictAddr),
  .predictVal(robPredictVal),

  .rfFlag(robRfFlag),
  .rfRobId(robRfId),
  .rfDest(robRfDest),
  .rfValue(robRfVal),

  .rsFlag(rsOutFlag),
  .rsId(rsOutDest),
  .rsValue(rsOutVal),

  .loadFlag(lsbOutFlag),
  .loadId(lsbOutDest),
  .loadValue(lsbOutVal),
  .storeFlag(robStoreFlag),
  .storeId(robStoreId)
);

BranchPredictor#(
  .TABLE_WIDTH(6)
) branchPredictor(
  .resetIn(rst_in),
  .clockIn(clk_in),
  .readyIn(rdy_in),
  .predictAddr(iuInsAddr),
  .jump(predictJump),
  .updateFlag(robPredictFlag),
  .updateAddr(robPredictAddr),
  .updateVal(robPredictVal)
);

RegisterFile#(
  .ROB_WIDTH(ROB_WIDTH)
) registerFile(
  .clockIn(clk_in),
  .resetIn(rst_in),
  .readyIn(rdy_in),
  .clearIn(clear),

  .rdFlag(iuRdFlag),
  .rdAddr(iuRdAddr),
  .rdDest(iuRdDest),
  .rs1Addr(iuRs1Addr),
  .rs2Addr(iuRs2Addr),
  .rs1Value(rfRs1Val),
  .rs1Rename(rfRs1Rename),
  .rs1Busy(rfRs1Busy),
  .rs2Value(rfRs2Val),
  .rs2Rename(rfRs2Rename),
  .rs2Busy(rfRs2Busy),

  .writeFlag(robRfFlag),
  .robId(robRfId),
  .writeAddr(robRfDest),
  .writeValue(robRfVal)
);

ICache#(
  .BLOCK_OFFSET(2),
  .CACHE_WIDTH(8),
  .TAG_WIDTH(7)
) icache(
  .clockIn(clk_in),
  .resetIn(rst_in),
  .readyIn(rdy_in),
  .addrIn(iuFetchOut),
  .hit(icacheHit),
  .dataOut(icacheData),
  .validIn(memIcacheOk),
  .dataIn(memData),
  .memFlag(icacheMemFlag),
  .addrOut(icacheAddr)
);

MemoryController memoryController(
  .clockIn(clk_in),
  .resetIn(rst_in),
  .readyIn(rdy_in),
  .clearIn(clear),
  .dataOut(memData),

  .icacheFlag(icacheMemFlag),
  .icacheAddr(icacheAddr),
  .icacheOk(memIcacheOk),

  .lsbFlag(lsbMemFlag),
  .lsbOp(lsbMemOp),
  .lsbAddr(lsbMemAddr),
  .lsbIn(lsbMemData),
  .lsbOk(memLsbOk),

  .ramSelect(mem_wr),
  .ramAddr(mem_a),
  .ramOut(mem_dout),
  .ramIn(mem_din),
  .ioBufferFull(io_buffer_full)
);

LoadStoreBuffer#(
  .ROB_WIDTH(ROB_WIDTH),
  .LSB_WIDTH(LSB_WIDTH)
) loadStoreBuffer(
  .clockIn(clk_in),
  .resetIn(rst_in),
  .readyIn(rdy_in),
  .clearIn(clear),

  .addFlag(iuLsbFlag),
  .addOp(iuLsbOp),
  .addVj(iuRs1),
  .addQj(iuRs1Id),
  .addQjBusy(iuRs1Busy),
  .addVk(iuRs2),
  .addQk(iuRs2Id),
  .addQkBusy(iuRs2Busy),
  .addImm(iuLsbImm),
  .addDest(iuRdDest),
  .full(lsbFull),

  .aluFlag(rsOutFlag),
  .aluVal(rsOutVal),
  .aluDest(rsOutDest),

  .robFLag(robStoreFlag),
  .robDest(robStoreId),
  
  .outFlag(lsbOutFlag),
  .outVal(lsbOutVal),
  .outDest(lsbOutDest),

  .memOutFlag(lsbMemFlag),
  .memOp(lsbMemOp),
  .memAddr(lsbMemAddr),
  .memDataOut(lsbMemData),
  .memDataIn(memData),
  .memOkFlag(memLsbOk)
);

ReservationStation#(
  .ROB_WIDTH(ROB_WIDTH),
  .RS_WIDTH(RS_WIDTH)
) reservationStation(
  .clockIn(clk_in),
  .resetIn(rsReset),
  .readyIn(rdy_in),

  .addFlag(iuRsFlag),
  .addOp(iuRsOp),
  .addVj(iuRs1),
  .addQj(iuRs1Id),
  .addQjBusy(iuRs1Busy),
  .addVk(iuRs2),
  .addQk(iuRs2Id),
  .addQkBusy(iuRs2Busy),
  .addDest(iuOutDest),
  .full(rsFull),

  .lsbFlag(lsbOutFlag),
  .lsbVal(lsbOutVal),
  .lsbDest(lsbOutDest),

  .outFlag(rsOutFlag),
  .outVal(rsOutVal),
  .outDest(rsOutDest)
);

endmodule