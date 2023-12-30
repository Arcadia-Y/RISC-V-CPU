// Memory Controller
module MemoryController(
    input wire  clockIn,
    input wire  resetIn,
    input wire  readyIn,

    input wire  clearIn, // for wrong branch prediction
    output wire [31:0] dataOut,

    // icache
    input wire  icacheFlag,
    input wire  [31:0] icacheAddr,
    output wire icacheOk,

    // LSB
    input wire  lsbFlag,
    input wire  [2:0] lsbOp,
    input wire  [31:0] lsbAddr,
    input wire  [31:0] lsbIn,
    output wire lsbOk,

    // ram
    output wire ramSelect, // read:1, write:0
    output wire [31:0] ramAddr,
    output wire [7:0] ramOut,
    input wire  [7:0] ramIn,
    input wire  ioBufferFull
);

parameter IDLE = 2'b00;
parameter IFETCH = 2'b01;
parameter LOAD = 2'b10;
parameter STORE = 2'b11;

reg [1:0] state; // state for FSM 
reg [1:0] selector; // byte selector
reg [1:0] endPos; // 00 for byte, 01 for halfword, 11 for word
reg [31:0] buffer;
reg lsbOkReg;
reg icacheOkReg;
reg [7:0] ramOutReg;
reg ramSelectReg;
reg [31:0] ramAddrReg;
wire [1:0] selectorPlus = selector + 1'b1;
wire ioStall = lsbAddr[17:16] == 2'b11 & ioBufferFull;

assign dataOut = buffer;
assign lsbOk = lsbOkReg;
assign icacheOk = icacheOkReg;
assign ramSelect = ramSelectReg;
assign ramOut = ramOutReg;
assign ramAddr = state == IDLE ? 
                   lsbFlag & ~lsbOp[2] & ~ioStall? 
                     lsbAddr :
                     icacheAddr :
                 ramAddrReg;

`ifdef DEBUG
integer fileHandle;
initial begin
    fileHandle = $fopen("mem.txt");
end
`endif

always @(posedge clockIn) begin
    if (resetIn) begin
        state <= IDLE;
        selector <= 0;
        endPos <= 0;
        buffer <= 0;
        lsbOkReg <= 0;
        icacheOkReg <= 0;
        ramOutReg <= 0;
        ramSelectReg <= 0;
        ramAddrReg <= 0;
    end else if (clearIn & readyIn & (state != STORE)) begin
        state <= IDLE;
        selector <= 0;
        lsbOkReg <= 0;
        icacheOkReg <= 0;
        endPos <= 0;
        ramOutReg <= 0;
        ramSelectReg <= 0;
    end else if (readyIn) begin
        case (state)
        IDLE: begin
            lsbOkReg <= 0;
            icacheOkReg <= 0;
            if (lsbFlag & ~ioStall) begin // priorize lsb
                endPos <= lsbOp[1:0];
                if (lsbOp[2]) begin // STORE
                    state <= STORE;
                    selector <= 0;
                    ramOutReg <= lsbIn[7:0];
                    ramSelectReg <= 1;
                    ramAddrReg <= lsbAddr;
                end else begin // LOAD
                    state <= LOAD;
                    if (lsbOp[1:0] == 2'b00) begin
                        selector <= 0;
                        ramAddrReg <= 0;
                    end else begin
                        selector <= 1;
                        ramAddrReg <= lsbAddr + 1;
                    end
                end
            end else if (icacheFlag) begin
                state <= IFETCH;
                selector <= 1;
                ramAddrReg <= icacheAddr + 1;
            end
        end
        IFETCH: begin
            case (selector)
                2'b01: buffer[7:0] <= ramIn; 
                2'b10: buffer[15:8] <= ramIn;
                2'b11: buffer[23:16] <= ramIn;
                2'b00: buffer[31:24] <= ramIn;
            endcase
            if (selector == 2'b00) begin
                state <= IDLE;
                icacheOkReg <= 1;
                ramAddrReg <= 0;
            end else begin
                selector <= selectorPlus;
                ramAddrReg <= ramAddrReg + 1;
            end
        end
        LOAD: begin
            case (selector)
                2'b01: buffer[7:0] <= ramIn; 
                2'b10: buffer[15:8] <= ramIn;
                2'b11: buffer[23:16] <= ramIn;
                2'b00: begin
                    case (endPos)
                        2'b00: buffer[7:0] <= ramIn; // byte
                        2'b01: buffer[15:8] <= ramIn; // halfword
                        default: buffer[31:24] <= ramIn; // word
                    endcase
                end
            endcase
            if (selector == 2'b00) begin
                state <= IDLE;
                lsbOkReg <= 1;
            end else if (selector == endPos) begin
                selector <= 0;
                ramAddrReg <= 0;
            end else begin
                selector <= selectorPlus;
                ramAddrReg <= ramAddrReg + 1;
            end
        end
        STORE: begin
            `ifdef DEBUG
            $fdisplay(fileHandle, "mem %d <- %d", ramAddr, ramOut);
            `endif
            if (selector == endPos) begin
                selector <= 0;
                state <= IDLE;
                lsbOkReg <= 1;
                ramSelectReg <= 0;
                ramAddrReg <= 0;
            end else begin
                selector <= selectorPlus;
                ramAddrReg <= ramAddrReg + 1;
                case (selector)
                    2'b00: ramOutReg <= lsbIn[15:8];
                    2'b01: ramOutReg <= lsbIn[23:16];
                    2'b10: ramOutReg <= lsbIn[31:24];
                endcase
            end
        end
        endcase
    end
end

endmodule