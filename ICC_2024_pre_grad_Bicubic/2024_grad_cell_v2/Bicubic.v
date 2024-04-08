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

wire [13:0] addr;
wire [7:0] data;
reg [6:0] addr_rom_x, addr_rom_y;
reg [7:0] arr_data[0:3];
reg [5:0] cnt_H, cnt_W;
reg [2:0] cnt;
reg [2:0] x_time;
reg [`ACC+9:0] inv_x, inv_y;
wire [`ACC+6:0] float_temp1;
wire [`ACC+9:0] float_temp2;
wire [5:0] float_temp3;
wire [`ACC+6:0] float_temp;
reg [`ACC+6:0] float_x, float_y;
wire check_x, check_y;
wire [6:0] addr_x, addr_y;
wire [`ACC-1:0] inter_xy;
reg enable;
integer i;
assign addr = ((addr_rom_y << 6) + (addr_rom_y << 5)) + ((addr_rom_y << 2) + addr_rom_x);

assign float_temp1 = (currState == CHECK && cnt) ? (H0<<`ACC)  : (V0<<`ACC);
assign float_temp2 = (currState == CHECK && cnt) ? inv_x : inv_y;
assign float_temp3 = (currState == CHECK && cnt) ? (TW - 1) : (TH - 1);
assign float_temp = float_temp1 + (float_temp2 / float_temp3);

assign check_x = (float_x[(`ACC-1):0] == 0) ? 1'b0 : 1'b1;
assign check_y = (float_y[(`ACC-1):0] == 0) ? 1'b0 : 1'b1;

assign addr_x = float_x[(`ACC+6):`ACC];
assign addr_y = float_y[(`ACC+6):`ACC];

assign inter_xy = (x_time) ? float_x[`ACC-1:0] : float_y[`ACC-1:0];

wire p_valid;
wire signed [`ACC+9:0] p;
reg [7:0] arr_p[0:3];
reg [7:0] result_p;
reg [13:0] output_addr;

ImgROM u_ImgROM (.Q(data), .CLK(~CLK), .CEN(p_valid), .A(addr));
ResultSRAM u_ResultSRAM(.Q(), .CLK(~CLK), .CEN(p_valid), .WEN(currState != WRITE), .A(output_addr), .D(result_p));
INTER u_INTER(.CLK(CLK), .RST(RST), .enable(enable), .PIX_0(arr_data[0]), .PIX_1(arr_data[1]), .PIX_2(arr_data[2]), .PIX_3(arr_data[3]), .INTER_XY(inter_xy), .valid(p_valid), .p(p));

always @(*) begin
    case (currState)
        INTER_X, INTER_Y: enable = ((cnt>2)) ? 1'b1 : 1'b0;
        INTER_XY: enable = ((x_time && cnt>2)|| (x_time == 0 && cnt>0)) ? 1'b1 : 1'b0;
        default: enable = 1'b0;
    endcase
end

always @(posedge CLK or posedge RST) begin
    if (RST) begin
        float_x <= {(`ACC+7){1'b0}};
        float_y <= {(`ACC+7){1'b0}};
    end
    else if (currState == CHECK)begin
        case (cnt)
            3'b1: float_x <= float_temp; 
            3'b0: float_y <= float_temp;
        endcase
    end
end


always @(*) begin
    if ({check_y, check_x} == 2'b00) result_p = data;
    else begin
        case (p[`ACC+9 : `ACC+8])
            2'b00: result_p = p[(`ACC+7):`ACC]+p[(`ACC-1)];
            2'b01: result_p = 8'd255;
            default: result_p = 8'd0;
        endcase
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) x_time <= 3'd0;
    else begin
        case (currState)
            CHECK: x_time <= (check_x) ? 3'd4 : (check_y) ? 3'd0 : 3'd1;
            INTER_XY: x_time <= (p_valid) ? (x_time - 1) : x_time;
        endcase
    end
end


always @(posedge CLK or posedge RST) begin
    if (RST) cnt <= 3'd0;
    else begin
        case (currState)
            CHECK   : cnt <= (cnt == 2) ? 0 : cnt+1;
            IDLE, WRITE, FINISH : cnt <= 0;
            default : cnt <= (p_valid) ? 3'd0 : cnt+1;
        endcase
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) for (i=0; i<4; i=i+1) arr_p[i] <= 8'd0;
    else if (currState == INTER_XY & p_valid) begin
        case (x_time-1)
            2'd3: arr_p[0]<=result_p;
            2'd2: arr_p[1]<=result_p;
            2'd1: arr_p[2]<=result_p;
            2'd0: arr_p[3]<=result_p;
        endcase
    end
end


always @(posedge CLK or posedge RST) begin
    if (RST) begin
        addr_rom_x <= 7'd0;
        addr_rom_y <= 7'd0; 
    end 
    else begin
        case (currState)
            INTER_: begin
                addr_rom_x <= addr_x;
                addr_rom_y <= addr_y; 
            end 
            INTER_X: begin
                addr_rom_y <= addr_y;
                case (cnt)
                    0: addr_rom_x <= (addr_x - 1);
                    1: addr_rom_x <= addr_x;
                    2: addr_rom_x <= (addr_x + 1);
                    3: addr_rom_x <= (addr_x + 2);
                endcase
            end
            INTER_Y: begin  
                addr_rom_x <= addr_x;
                case (cnt)
                    0: addr_rom_y <= (addr_y - 1);
                    1: addr_rom_y <= addr_y ;
                    2: addr_rom_y <= (addr_y + 1);
                    3: addr_rom_y <= (addr_y + 2);
                endcase
            end
            INTER_XY: begin 
                addr_rom_y <= addr_y - x_time + 3;
                case (cnt)
                    0: addr_rom_x <= (addr_x - 1);
                    1: addr_rom_x <= addr_x;
                    2: addr_rom_x <= (addr_x + 1);
                    3: addr_rom_x <= (addr_x + 2);
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
    if (RST) begin
        inv_x <= {(`ACC+10){1'b0}};
        inv_y <= {(`ACC+10){1'b0}};
    end
    else begin
        case (currState)
            WRITE: begin
                inv_x <= (cnt_W == (TW - 1)) ? {(`ACC+10){1'b0}} : inv_x + ((SW - 1) << `ACC);
                inv_y <= (cnt_W == (TW - 1)) ? inv_y + ((SH - 1) << `ACC) : inv_y;
            end
            FINISH: begin
                inv_x <= {(`ACC+10){1'b0}};
                inv_y <= {(`ACC+10){1'b0}};
            end
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
        INTER_X, INTER_Y:  arr_data[cnt-1] <= data;
        INTER_XY: begin
            if (x_time) arr_data[cnt-1] <= data;
            else for (i=0; i<4; i=i+1) arr_data[i] <= arr_p[i];
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
            if (cnt == 2) begin
                case ({check_y, check_x})
                    2'b00:   nextState = INTER_;
                    2'b01:   nextState = INTER_X;
                    2'b10:   nextState = INTER_Y;
                    default: nextState = INTER_XY;
                endcase
            end
            else nextState = CHECK;
        end
        INTER_   : nextState = (cnt ==  1) ? WRITE : INTER_;
        INTER_X  : nextState = (p_valid) ? WRITE : INTER_X;
        INTER_Y  : nextState = (p_valid) ? WRITE : INTER_Y;
        INTER_XY : nextState = (p_valid && !x_time) ? WRITE : INTER_XY;
        WRITE    : nextState = (cnt_W == (TW-1) && cnt_H == (TH-1)) ? FINISH : CHECK;
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
input [`ACC-1:0]  INTER_XY,
output reg valid,
output reg signed [`ACC+9:0] p);

wire signed [10:0] a, b, c, d;
assign a = ({PIX_1, 1'b0} + PIX_1) + PIX_3  - PIX_0  - ({PIX_2, 1'b0} + PIX_2) ;
assign b = {2'b0, PIX_0, 1'b0} - ({1'b0, PIX_1, 2'b0} + {3'b0, PIX_1}) + {1'b0, PIX_2, 2'b0} - {3'b0, PIX_3};
assign c = PIX_2 - PIX_0;
assign d = {PIX_1, 1'b0};

reg [`ACC+`ACC-1:0] x_temp;
reg [2:0] cnt;
reg signed [`ACC+25:0] const_temp;

always @(posedge CLK or posedge RST) begin
    if (RST) cnt <= 4'd0;
    else if (enable) cnt <= (cnt == 4) ? 4'd0 : cnt + 1;
    else cnt <= 4'd0;
end
always @(posedge CLK or posedge RST) begin
    if (RST) x_temp <= {(`ACC+`ACC-1){1'b0}};
    else if (enable) 
        case (cnt)
        4'd0: x_temp <= INTER_XY;
        4'd1, 4'd2: x_temp <= (x_temp * INTER_XY) >> `ACC;
        default: x_temp <= x_temp;
    endcase
end

always @(posedge CLK or posedge RST) begin
    if (RST) const_temp <= {(`ACC+26){1'b0}};
    else if (enable) 
        case (cnt)
        4'd0: const_temp <= d << (`ACC-1);
        4'd1: const_temp <= ((c << (`ACC-1)) * $signed(x_temp)) >>> `ACC; 
        4'd2: const_temp <= ((b << (`ACC-1)) * $signed(x_temp)) >>> `ACC; 
        4'd3: const_temp <= ((a << (`ACC-1)) * $signed(x_temp)) >>> `ACC;
        default: const_temp <= const_temp;
    endcase
end


always @(posedge CLK or posedge RST) begin
    if (RST) p <= {(`ACC+10){1'b0}};
    else if (enable)begin
        case (cnt)
            4'd1: p <= const_temp;
            4'd2: p <= p + const_temp;
            4'd3: p <= p + const_temp;
            4'd4: p <= p + const_temp;
        endcase
    end
end

always @(posedge CLK or posedge RST) begin
    if (RST) valid <= 1'd0;
    else valid <= (cnt == 4) ? 1'd1 : 1'd0;
end

endmodule


