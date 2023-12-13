// Memory Controller
module MemoryController#(
    parameter ADDR_WIDTH = 17
)(
    input wire  clockIn,
    input wire  resetIn,
    input wire  readyIn,

    input wire  clearIn, // for wrong branch prediction
    output wire dataOut,

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
    output wire [ADDR_WIDTH-1:0] ramAddr,
    output wire [7:0] ramOut,
    input wire  [7:0] ramIn
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
wire selectorPlus = selector + 1'b1;

assign dataOut = buffer;
assign lsbOk = lsbOkReg;
assign icacheOk = icacheOkReg;
assign ramSelect = state == STORE ? 0 : 1;
assign ramAddr = state == IDLE ? 
                    lsbFlag ? 
                        lsbAddr[ADDR_WIDTH-1:0] :
                    icacheAddr[ADDR_WIDTH-1:0] :
                 state == IFETCH ? 
                    icacheAddr[ADDR_WIDTH-1:0] + selector :
                lsbAddr[ADDR_WIDTH-1:0] + selector;
assign ramOut = state != STORE ? 0  :
                selector == 2'b00 ? lsbIn[7:0] :
                selector == 2'b01 ? lsbIn[15:8] :
                selector == 2'b10 ? lsbIn[23:16] :
                lsbIn[31:24];

always @(posedge clockIn) begin
    if (resetIn) begin
        state <= IDLE;
        selector <= 0;
        endPos <= 0;
        buffer <= 0;
        lsbOkReg <= 0;
        icacheOkReg <= 0;
    end else if (clearIn & readyIn & (state != STORE)) begin
        state <= IDLE;
        selector <= 0;
        lsbOkReg <= 0;
        icacheOkReg <= 0;
        endPos <= 0;
    end else if (readyIn) begin
        case (state)
        IDLE: begin
            lsbOkReg <= 0;
            icacheOkReg <= 0;
            if (lsbFlag) begin // priorize lsb
                endPos <= lsbOp[1:0];
                if (lsbOp[2]) begin // STORE
                    state <= STORE;
                    selector <= 0;
                end else begin // LOAD
                    state <= LOAD;
                    if (lsbOp[1:0] == 2'b00)
                        selector <= 0;
                    else
                        selector <= 1;
                end
            end else if (icacheFlag) begin
                state <= IFETCH;
                selector <= 1;
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
            end else
                selector <= selectorPlus;
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
            end else if (selector == endPos)
                selector <= 0;
            else
                selector <= selectorPlus;
        end
        STORE: begin
            if (selector == endPos) begin
                selector <= 0;
                state <= IDLE;
                lsbOkReg <= 1;
            end else
                selector <= selectorPlus;
        end
        endcase
    end
end

endmodule