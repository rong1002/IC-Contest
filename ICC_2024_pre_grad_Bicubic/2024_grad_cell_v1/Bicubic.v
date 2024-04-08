`define  ACC 16

module Bicubic (
input CLK,
input RST,
input [6:0] V0,
input [6:0] H0,
input [4:0] SW,
input [4:0] SH,
input [5:0] TW,
input [5:0] TH,
output wire DONE);

reg [2:0] currState, nextState;
localparam IDLE     = 3'd0;
localparam CHECK    = 3'd1;
localparam INTER_XY = 3'd2;
localparam INTER_X  = 3'd3;
localparam INTER_Y  = 3'd4;
localparam INTER_   = 3'd5;
localparam WRITE    = 3'd6;
localparam FINISH   = 3'd7;

reg [13:0] addr;
wire [7:0] data;

reg [7:0] arr_data[0:3];
reg [5:0] cnt_H, cnt_W;
reg delay;
reg [2:0] cnt;
reg [2:0] x_time;
reg y_time;

wire [(`ACC+6):0] float_x, float_y;
reg [(`ACC+6):0] inter_xy;
assign float_x = (H0 << `ACC) + ((cnt_W * ((SW - 1) << `ACC)) / (TW - 1));
assign float_y = (V0 << `ACC) + ((cnt_H * ((SH - 1) << `ACC)) / (TH - 1));

wire check_x, check_y;
assign check_x = (float_x[(`ACC-1):0] == 0) ? 1'b0 : 1'b1;
assign check_y = (float_y[(`ACC-1):0] == 0) ? 1'b0 : 1'b1;

wire [6:0] addr_x, addr_y;
assign addr_x = float_x[(`ACC+6):`ACC];
assign addr_y = float_y[(`ACC+6):`ACC];
integer i;

reg enable;
always @(*) begin
    case (currState)
        INTER_X, INTER_Y: enable = (cnt==4) ? 1'b1 : 1'b0;
        INTER_XY: begin
            if (x_time != 0 && cnt==4) enable = 1'b1;
            else if (x_time == 0 && cnt==1) enable = 1'b1;
            else enable = 1'b0;
        end
        default: enable = 1'b0;
    endcase
end

wire p_valid;
wire signed [(`ACC+9):0] p;
reg [7:0] arr_p[0:3];
reg [7:0] result_p;
reg [13:0] output_addr;
wire read_enable;
assign read_enable = 1'd0;
ImgROM u_ImgROM (.Q(data), .CLK(~CLK), .CEN(read_enable), .A(addr));
ResultSRAM u_ResultSRAM(.Q(), .CLK(~CLK), .CEN(read_enable), .WEN(currState != WRITE), .A(output_addr), .D(result_p));
INTER u_INTER(.CLK(CLK), .RST(RST), .enable(enable), .PIX_0(arr_data[0]), .PIX_1(arr_data[1]), .PIX_2(arr_data[2]), .PIX_3(arr_data[3]), .INTER_XY(inter_xy), .valid(p_valid), .p(p));

always @(*) begin
    case (currState)
        INTER_X: inter_xy = float_x;
        INTER_Y: inter_xy = float_y;
        INTER_XY: inter_xy = (x_time != 0) ? float_x : float_y;
        default: inter_xy = float_x;
    endcase
end

always @(*) begin
    if ({check_y, check_x} == 2'b00) result_p = data;
    else begin
        if (p[`ACC+9]) result_p = 8'd0;
        else if (p[`ACC+8] != 0) result_p = 8'd255;
        else result_p = p[(`ACC+7):`ACC]+p[(`ACC-1)];
        // else result_p = (p[(`ACC-1)]) ? p[(`ACC+7):`ACC]+1 : p[(`ACC+7):`ACC];
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) x_time <= 3'd0;
    else begin
        case (currState)
            CHECK: x_time <= (check_x & check_y) ? 3'd4 : 3'd0;
            INTER_XY: x_time <= (p_valid) ? (x_time - 1) : x_time;
            default: x_time <= 3'd0;
        endcase
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) y_time <= 1'd0;
    else begin
        case (currState)
            CHECK: y_time <= (check_x & check_y) ? 1'd1 : 1'd0;
            INTER_XY: y_time <= (!x_time && cnt == 4) ? (y_time - 1) : y_time;
            default: y_time <= 1'd0;
        endcase
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) cnt <= 3'd0;
    else begin
        case (currState)
            CHECK   : cnt<=0;
            INTER_XY: cnt <= (p_valid) ? 3'd0 : (delay) ? cnt+1 : cnt;
            default : cnt <= (delay) ? cnt+1 : cnt;
        endcase
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) for (i=0; i<4; i=i+1) arr_p[i] <= 8'd0;
    else if (currState == INTER_XY) begin
        if (p_valid) begin
            case (x_time-1)
                2'd3: arr_p[0]<=result_p;
                2'd2: arr_p[1]<=result_p;
                2'd1: arr_p[2]<=result_p;
                2'd0: arr_p[3]<=result_p;
            endcase
        end
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) addr <= 14'b0;
    else begin
        case (currState)
            INTER_: begin
                addr <= (100 * addr_y) + addr_x;
            end 
            INTER_X: begin
                case (cnt)
                    0: addr <= (100 * (addr_y)) + (addr_x - 1);
                    1: addr <= (100 * (addr_y)) + (addr_x);
                    2: addr <= (100 * (addr_y)) + (addr_x + 1);
                    3: addr <= (100 * (addr_y)) + (addr_x + 2);
                endcase
            end
            INTER_Y: begin
                case (cnt)
                    0: addr <= (100 * (addr_y - 1)) + (addr_x);
                    1: addr <= (100 * (addr_y)) + (addr_x);
                    2: addr <= (100 * (addr_y + 1)) + (addr_x);
                    3: addr <= (100 * (addr_y + 2)) + (addr_x);
                endcase
            end
            INTER_XY: begin
                case (cnt)
                    0: addr <= (100 * ((addr_y - 1)+(4-x_time))) + (addr_x - 1);
                    1: addr <= (100 * ((addr_y - 1)+(4-x_time))) + (addr_x);
                    2: addr <= (100 * ((addr_y - 1)+(4-x_time))) + (addr_x + 1);
                    3: addr <= (100 * ((addr_y - 1)+(4-x_time))) + (addr_x + 2);
                endcase
            end
        endcase
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) begin
        output_addr <= 14'd0;
    end
    else begin
        case (currState)
            WRITE: output_addr <= output_addr + 1;
            FINISH: output_addr <= 14'd0;
            default: output_addr <= output_addr;
        endcase
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) delay <= 1'b0;
    else begin
        case (currState)
            CHECK   : delay<=0;
            INTER_XY: delay <= (p_valid) ? 1'b0 : (delay) ? 1'b0 : 1'b1;
            default : delay <= (delay) ? 1'b0 : 1'b1;
        endcase
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) cnt_W <= 8'd0;
    else begin
        case (currState)
            WRITE: cnt_W <= (cnt_W == TW-1) ? 8'd0 : cnt_W + 1;
            FINISH: cnt_W <= 8'd0;
            default: cnt_W <= cnt_W;
        endcase
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) cnt_H <= 8'd0;
    else begin
        case (currState)
            WRITE: cnt_H <= (cnt_W == TW-1) ? cnt_H + 1 : cnt_H;
            FINISH: cnt_H <= 8'd0;
            default: cnt_H <= cnt_H;
        endcase
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) for (i=0; i<4; i=i+1) arr_data[i] <= 8'd0;
    else begin
        case (currState)
        INTER_X, INTER_Y:  arr_data[cnt-1] <= (!delay) ? data : arr_data[cnt-1];
        INTER_XY: begin
            if (!delay && x_time != 0) arr_data[cnt-1] <= data;
            else if (x_time == 0) begin
                arr_data[0] <= arr_p[0];
                arr_data[1] <= arr_p[1];
                arr_data[2] <= arr_p[2];
                arr_data[3] <= arr_p[3];
            end
        end
        endcase
    end
end

assign DONE = (currState == FINISH) ? 1'b1 : 1'b0;

// ----- FSM -----
always @(*) begin
    case (currState)
        IDLE:  nextState = CHECK;
        CHECK: begin
            case ({check_y, check_x})
                2'b00:   nextState = INTER_;
                2'b01:   nextState = INTER_X;
                2'b10:   nextState = INTER_Y;
                default: nextState = INTER_XY;
            endcase
        end
        INTER_   : nextState = (cnt ==  1) ? WRITE : INTER_;
        INTER_X  : nextState = (p_valid) ? WRITE : INTER_X;
        INTER_Y  : nextState = (p_valid) ? WRITE : INTER_Y;
        INTER_XY : nextState = (p_valid && !x_time) ? WRITE : INTER_XY;
        WRITE    : nextState = (output_addr == TW*TH-1) ? FINISH : CHECK;
        FINISH:  nextState = IDLE;
        default: nextState = IDLE;
    endcase
end

always @(posedge CLK or posedge RST) begin
    if(RST) currState <= IDLE;
    else currState <= nextState;
end

endmodule



module INTER (
input CLK,
input RST,
input enable,
input [7:0] PIX_0,
input [7:0] PIX_1,
input [7:0] PIX_2,
input [7:0] PIX_3,
input [22:0] INTER_XY,
output reg valid,
output reg signed [25:0] p);

wire signed [10:0] a, b, c, d;
assign a = ({PIX_1, 1'b0} + PIX_1) + PIX_3  - PIX_0  - ({PIX_2, 1'b0} + PIX_2) ;
assign b = {2'b0, PIX_0, 1'b0} - ({1'b0, PIX_1, 2'b0} + {3'b0, PIX_1}) + {1'b0, PIX_2, 2'b0} - {3'b0, PIX_3};
assign c = PIX_2 - PIX_0;
assign d = {PIX_1, 1'b0};

reg signed [(`ACC+10):0] const_abcd;
reg [(`ACC+`ACC-1):0] x_temp;
reg [2:0] cnt;
wire signed [(`ACC+25):0] const_temp;
assign const_temp = (const_abcd * $signed(x_temp)) >>> `ACC;

always @(posedge CLK or posedge RST) begin
    if (RST) cnt <= 4'd0;
    else if (enable) cnt <= 4'd0;
    else cnt <= (cnt == 4) ? 4'd4 : cnt + 1;
end

always @(*) begin
    case (cnt)
        4'd0: const_abcd = d << (`ACC-1);
        4'd1: const_abcd = c << (`ACC-1);
        4'd2: const_abcd = b << (`ACC-1);
        4'd3: const_abcd = a << (`ACC-1);
        default : const_abcd = 0;
    endcase
end

always @(posedge CLK or posedge RST) begin
    if (RST) x_temp <= 31'd0;
    else if (enable) x_temp <= 31'd0;
    else x_temp <= (cnt == 0) ? INTER_XY[(`ACC-1):0] : (x_temp * INTER_XY[(`ACC-1):0]) >> `ACC;
end

always @(posedge CLK or posedge RST) begin
    if (RST) p <= 28'd0;
    else if (enable) p <= 28'd0;
    else begin
        case (cnt)
            4'd0: p <= const_abcd;
            4'd1: p <= p + const_temp;
            4'd2: p <= p + const_temp;
            4'd3: p <= p + const_temp;
        endcase
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) valid <= 1'd0;
    else if (enable) valid <= 1'd0;
    else valid <= (cnt == 3) ? 1'd1 : 1'd0;
end

endmodule
