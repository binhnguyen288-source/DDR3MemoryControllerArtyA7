`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/08/2023 02:01:52 AM
// Design Name: 
// Module Name: ddr3_controller
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module oddr_pinout(
    input clk,
    input data,
    output pin_out,
    input rst
);
    
    parameter rst_value = 1'b0;
    
    reg out_q;
    always @(posedge clk)
        out_q <= rst ? rst_value : data;
        
    OBUF #(
      .IOSTANDARD("SSTL135"), // Specify the output I/O standard
      .SLEW("SLOW") // Specify the output slew rate
   ) OBUF_inst (
      .O(pin_out),     // Buffer output (connect directly to top-level port)
      .I(out_q)      // Buffer input
   );

endmodule

module ddr3_controller(
    // user ports
    input rst_i,
    input clk,
    input clk_90,
    input clk_ref,
    input clk_ddr,
    input[31:0] ram_addr,
    input wr_en,
    input[127:0] wr_data,
    input rd_en,
    output[127:0] rd_data,
    output accepted,
    output acked,
    // io ports
    output ddr3_reset_n,
    output ddr3_cke,
    output ddr3_ck_p,
    output ddr3_ck_n,
    output ddr3_ras_n,
    output ddr3_cas_n,
    output ddr3_we_n,
    output[2:0] ddr3_ba,
    output[13:0] ddr3_addr,
    output ddr3_odt,
    output[1:0] ddr3_dm,
    inout[1:0] ddr3_dqs_p,
    inout[1:0] ddr3_dqs_n,
    inout[15:0] ddr3_dq
);
    
    
    assign ddr3_odt = 1'b0;
    assign ddr3_dm = 2'b00;
    
    
    OBUFDS #(
      .IOSTANDARD("DIFF_SSTL135"), // Specify the output I/O standard
      .SLEW("SLOW")           // Specify the output slew rate
   ) OBUFDS_inst (
      .O(ddr3_ck_p),     // Diff_p output (connect directly to top-level port)
      .OB(ddr3_ck_n),   // Diff_n output (connect directly to top-level port)
      .I(~clk)      // Buffer input
   );

    localparam CMD_NOP            = 4'b0111;
    localparam CMD_ACTIVE         = 4'b0011;
    localparam CMD_READ           = 4'b0101;
    localparam CMD_WRITE          = 4'b0100;
    localparam CMD_PRECHARGE      = 4'b0010;
    localparam CMD_REFRESH        = 4'b0001;
    localparam CMD_LOAD_MODE      = 4'b0000;
    localparam CMD_ZQCL           = 4'b0110;
    
   
    
    typedef enum {
        STATE_INIT,
        STATE_IDLE,
        STATE_ACTIVE,
        STATE_READ,
        STATE_WRITE,
        STATE_PRECHARGE,
        STATE_REFRESH,
        STATE_INVALID
    } STATE;
    STATE state_q = STATE_INVALID;
    STATE target_q = STATE_INVALID;
    STATE state_r;
    STATE target_r;
    
    
   
    
    
    
    reg[3:0] command_r;
    reg[13:0] addr_r;
    reg[2:0] bank_r;
    reg cke_r;
    reg reset_n_r;
    
    function int max(input int a, input int b);
        return a > b ? a : b;
    endfunction
    
    localparam clk_period_ns = 10;
    function int ns_to_clk(input int ns);
        return (ns + clk_period_ns - 1) / clk_period_ns;
    endfunction
    
    localparam tRFC = 160;
    localparam cRFC = ns_to_clk(160);
    localparam cMRD = 4;
    localparam cMOD = ns_to_clk(max(12 * clk_period_ns, 15));
    localparam cXPR = ns_to_clk(max(5 * clk_period_ns, tRFC + 10));
    localparam cDLLK = 512;
    localparam cZQInit = 512;
    localparam cRCD = ns_to_clk(14); // active to read/write
    localparam cRP = ns_to_clk(14);  // precharge period
    `ifndef XILINX_SIMULATOR
    localparam cRESET  = ns_to_clk(200_000) + 1;
    localparam cRSTCKE = ns_to_clk(500_000) + 1;
    `else
    localparam cRESET  = 100;
    localparam cRSTCKE = 100;
    `endif
    
    localparam REFRESH_CTR_Q_INIT = cZQInit + cMOD + 3 * cMRD + cXPR + cRSTCKE + cRESET;
    localparam REFRESH_PERIOD_CK  = 781;
    
    reg[16:0] refresh_ctr_q;
    
    always_ff @(posedge clk) begin
        if (rst_i)
            refresh_ctr_q <= REFRESH_CTR_Q_INIT;
        else if (|refresh_ctr_q)
            refresh_ctr_q <= refresh_ctr_q - 1;
        else
            refresh_ctr_q <= REFRESH_PERIOD_CK;
    end
    
    reg need_refresh_q = 1'b0;
    always_ff @(posedge clk) begin
        if (rst_i)
            need_refresh_q <= 1'b0;
        else if (~|refresh_ctr_q)
            need_refresh_q <= 1'b1;
        else if (state_q == STATE_REFRESH)
            need_refresh_q <= 1'b0;
    end
    
    
    
    always_comb begin
        command_r = CMD_NOP;
        cke_r     = 1'b1;
        reset_n_r = 1'b1;
        addr_r    = 14'd0;
        bank_r    = 3'd0;
        case (state_q)
            STATE_INIT: begin
                if (refresh_ctr_q > cZQInit + cMOD + 3 * cMRD + cXPR + cRSTCKE)
                    reset_n_r = 1'b0;
                if (refresh_ctr_q > cZQInit + cMOD + 3 * cMRD + cXPR)
                    cke_r = 1'b0;
                if (refresh_ctr_q == cZQInit + cMOD + 3 * cMRD) begin
                    command_r = CMD_LOAD_MODE;
                    bank_r    = 3'b010;
                    addr_r    = 14'h0008;
                end
                if (refresh_ctr_q == cZQInit + cMOD + 2 * cMRD) begin
                    command_r = CMD_LOAD_MODE;
                    bank_r    = 3'b011;
                    addr_r    = 14'h0000;
                end
                if (refresh_ctr_q == cZQInit + cMOD + cMRD) begin
                    command_r = CMD_LOAD_MODE;
                    bank_r    = 3'b001;
                    addr_r    = 14'h0001;
                end
                if (refresh_ctr_q == cZQInit + cMOD) begin
                    command_r = CMD_LOAD_MODE;
                    bank_r    = 3'b000;
                    addr_r    = 14'h0320;
                end
                if (refresh_ctr_q == cZQInit) begin
                    command_r = CMD_ZQCL;
                    addr_r[10] = 1'b1;
                end
            end
            STATE_PRECHARGE: begin
                command_r = CMD_PRECHARGE;
                addr_r[10] = 1'b1;
            end
            STATE_ACTIVE: begin
                command_r = CMD_ACTIVE;
                bank_r = ram_addr[13:11];
                addr_r = ram_addr[27:14];
            end
            STATE_WRITE: begin
                command_r = CMD_WRITE;
                bank_r = ram_addr[13:11];
                addr_r[9:0] = ram_addr[10:1];
                addr_r[10] = 1'b1; // auto precharge
            end
            STATE_READ: begin
                command_r = CMD_READ;
                bank_r = ram_addr[13:11];
                addr_r[9:0] = ram_addr[10:1];
                addr_r[10] = 1'b1; // auto precharge
            end
            STATE_REFRESH: begin
                command_r = CMD_REFRESH;
            end
            default:;
        endcase
    end
    
    wire delaying;
    oddr_pinout #(.rst_value(1'b0)) oddr_reset_n(.clk(clk), .data(reset_n_r), .pin_out(ddr3_reset_n), .rst(rst_i));
    oddr_pinout #(.rst_value(1'b0)) oddr_cke(.clk(clk), .data(cke_r), .pin_out(ddr3_cke), .rst(rst_i));
    
    oddr_pinout #(.rst_value(1'b1)) oddr_ras_n(.clk(clk), .data(delaying ? 1'b1 : command_r[2]), .pin_out(ddr3_ras_n), .rst(rst_i));
    oddr_pinout #(.rst_value(1'b1)) oddr_cas_n(.clk(clk), .data(delaying ? 1'b1 : command_r[1]), .pin_out(ddr3_cas_n), .rst(rst_i));
    oddr_pinout #(.rst_value(1'b1)) oddr_we_n(.clk(clk), .data(delaying ? 1'b1 : command_r[0]), .pin_out(ddr3_we_n), .rst(rst_i));
    
    oddr_pinout oddr_ba0_n(.clk(clk), .data(bank_r[0]), .pin_out(ddr3_ba[0]), .rst(1'b0));
    oddr_pinout oddr_ba1_n(.clk(clk), .data(bank_r[1]), .pin_out(ddr3_ba[1]), .rst(1'b0));
    oddr_pinout oddr_ba2_n(.clk(clk), .data(bank_r[2]), .pin_out(ddr3_ba[2]), .rst(1'b0));
    
    generate
        for (genvar i = 0; i < 14; ++i) begin
            oddr_pinout oddr_addr(.clk(clk), .data(addr_r[i]), .pin_out(ddr3_addr[i]), .rst(1'b0));
        end
    endgenerate
    
    wire wr_ack = state_q == STATE_WRITE && !delaying;
    
    reg wr_ack_q = 1'b0;
    always_ff @(posedge clk) begin
        wr_ack_q <= rst_i ? 1'b0 : wr_ack;
    end
    
    reg[9:0] en_wr_q;
    always_ff @(posedge clk) begin
        if (rst_i) 
            en_wr_q <= 10'd0;
        else if (wr_ack)
            en_wr_q <= {4'b1111, en_wr_q[6:1]};
        else
            en_wr_q <= {1'b0, en_wr_q[9:1]};
    end
    reg[11:0] state_delay_q;
    reg[11:0] state_delay_r;
    always_comb begin
        if (delaying)
            state_delay_r = state_delay_q - 1;
        else begin
            case (command_r)
                CMD_PRECHARGE: state_delay_r = cRP;
                CMD_WRITE: state_delay_r = 21;
                CMD_READ: state_delay_r = 20;
                CMD_REFRESH: state_delay_r = cRFC;
                CMD_ACTIVE: state_delay_r = cRCD;
                default: state_delay_r = 12'h0;
            endcase
        end
    end
    
    always_ff @(posedge clk)
        state_delay_q <= rst_i ? 12'h0 : state_delay_r;
    
    assign delaying = |state_delay_q;
    
    always_comb begin
        state_r = state_q;
        target_r = target_q;
        case (state_q)
            STATE_INIT: begin
                if (~|refresh_ctr_q) begin
                    state_r = STATE_IDLE;
                end
            end
            STATE_IDLE: begin
                if (need_refresh_q) begin
                    state_r = STATE_PRECHARGE;
                    target_r = STATE_REFRESH;
                end
                else if (wr_en) begin
                    state_r = STATE_ACTIVE;
                    target_r = STATE_WRITE;
                end
                else if (rd_en) begin
                    state_r = STATE_ACTIVE;
                    target_r = STATE_READ;
                end
            end
            STATE_PRECHARGE: state_r = target_q;
            STATE_ACTIVE: state_r = target_q;
            STATE_READ: state_r = STATE_IDLE;
            STATE_WRITE: state_r = STATE_IDLE;
            STATE_REFRESH: state_r = STATE_IDLE;
            default:;
        endcase
    end
    wire rd_data_valid;
    assign accepted = (state_q == STATE_WRITE || state_q == STATE_READ) && !delaying;
    assign acked = wr_ack_q || rd_data_valid;
    always_ff @(posedge clk) begin
        if (rst_i) begin
            state_q <= STATE_INIT;
            target_q <= STATE_INIT;
        end else if (!delaying) begin
            state_q <= state_r;
            target_q <= target_r;
        end
    end
    
    
    
    reg[127:0] wr_data_phy;
    
    always_ff @(posedge clk) begin
        if (state_q == STATE_WRITE)
            wr_data_phy <= wr_data;
        else if (en_wr_q[2])
            wr_data_phy <= {32'h0, wr_data_phy[127:32]};
    end
    wire idelayctrl_rdy;
   // IDELAYCTRL: IDELAYE2/ODELAYE2 Tap Delay Value Control
   //             Artix-7
   // Xilinx HDL Language Template, version 2022.2

   (* IODELAY_GROUP = "groupinputdelay" *) // Specifies group name for associated IDELAYs/ODELAYs and IDELAYCTRL

   IDELAYCTRL IDELAYCTRL_inst (
      .RDY(idelayctrl_rdy),       // 1-bit output: Ready output
      .REFCLK(clk_ref), // 1-bit input: Reference clock input
      .RST(rst_i)        // 1-bit input: Active high reset input
   );

   // End of IDELAYCTRL_inst instantiation
    wire io_n_wr = ~en_wr_q[0];
    wire[1:0] dqs_out;
    wire[1:0] dqs_in_delayed;
    wire[15:0] dq_out;
    wire[15:0] dq_in_delayed;
    generate begin
            wire[1:0] dqs_in;
            wire[1:0] dqs_io_n_wr;
            for (genvar i = 0; i < 2; ++i) begin
               wire[1:0] dqs_in_delayed_unbuf;
               IOBUFDS #(
                  .DIFF_TERM("FALSE"),
                  .IBUF_LOW_PWR("FALSE"),   // Low Power - "TRUE", High Performance = "FALSE" 
                  .IOSTANDARD("DIFF_SSTL135"), // Specify the I/O standard
                  .SLEW("SLOW")            // Specify the output slew rate
               ) IOBUFDS_inst (
                  .O(dqs_in[i]),     // Buffer output
                  .IO(ddr3_dqs_p[i]),   // Diff_p inout (connect directly to top-level port)
                  .IOB(ddr3_dqs_n[i]), // Diff_n inout (connect directly to top-level port)
                  .I(dqs_out[i]),           // Buffer input
                  .T(dqs_io_n_wr[i])      // 3-state enable input, high=input, low=output
               );
               OSERDESE2 #(
                  .DATA_RATE_OQ("DDR"),   // DDR, SDR
                  .DATA_RATE_TQ("BUF"),   // DDR, BUF, SDR
                  .DATA_WIDTH(8),         // Parallel data width (2-8,10,14)
                  .INIT_OQ(1'b0),         // Initial value of OQ output (1'b0,1'b1)
                  .INIT_TQ(1'b0),         // Initial value of TQ output (1'b0,1'b1)
                  .SERDES_MODE("MASTER"), // MASTER, SLAVE
                  .SRVAL_OQ(1'b0),        // OQ output value when SR is used (1'b0,1'b1)
                  .SRVAL_TQ(1'b0),        // TQ output value when SR is used (1'b0,1'b1)
                  .TBYTE_CTL("FALSE"),    // Enable tristate byte operation (FALSE, TRUE)
                  .TBYTE_SRC("FALSE"),    // Tristate byte source (FALSE, TRUE)
                  .TRISTATE_WIDTH(1)      // 3-state converter width (1,4)
               )
               OSERDESE2_inst (
                  .OFB(),             // 1-bit output: Feedback path for data
                  .OQ(dqs_out[i]),               // 1-bit output: Data path output
                  // SHIFTOUT1 / SHIFTOUT2: 1-bit (each) output: Data output expansion (1-bit each)
                  .SHIFTOUT1(),
                  .SHIFTOUT2(),
                  .TBYTEOUT(),   // 1-bit output: Byte group tristate
                  .TFB(),             // 1-bit output: 3-state control
                  .TQ(dqs_io_n_wr[i]),               // 1-bit output: 3-state control
                  .CLK(clk_ddr),             // 1-bit input: High speed clock
                  .CLKDIV(clk),       // 1-bit input: Divided clock
                  // D1 - D8: 1-bit (each) input: Parallel data inputs (1-bit each)
                  .D1(1'b0),
                  .D2(1'b0),
                  .D3(1'b1),
                  .D4(1'b1),
                  .D5(1'b1),
                  .D6(1'b1),
                  .D7(1'b0),
                  .D8(1'b0),
                  .OCE(1'b1),             // 1-bit input: Output data clock enable
                  .RST(rst_i),             // 1-bit input: Reset
                  // SHIFTIN1 / SHIFTIN2: 1-bit (each) input: Data input expansion (1-bit each)
                  .SHIFTIN1(1'b0),
                  .SHIFTIN2(1'b0),
                  // T1 - T4: 1-bit (each) input: Parallel 3-state inputs
                  .T1(io_n_wr),
                  .T2(io_n_wr),
                  .T3(io_n_wr),
                  .T4(io_n_wr),
                  .TBYTEIN(1'b0),     // 1-bit input: Byte group tristate
                  .TCE(1'b1)              // 1-bit input: 3-state clock enable
               );
               (* IODELAY_GROUP = "groupinputdelay" *) // Specifies group name for associated IDELAYs/ODELAYs and IDELAYCTRL
               IDELAYE2 #(
                  .CINVCTRL_SEL("FALSE"),          // Enable dynamic clock inversion (FALSE, TRUE)
                  .DELAY_SRC("IDATAIN"),           // Delay input (IDATAIN, DATAIN)
                  .HIGH_PERFORMANCE_MODE("TRUE"), // Reduced jitter ("TRUE"), Reduced power ("FALSE")
                  .IDELAY_TYPE("FIXED"),           // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
                  .IDELAY_VALUE(31),                // Input delay tap setting (0-31)
                  .PIPE_SEL("FALSE"),              // Select pipelined mode, FALSE, TRUE
                  .REFCLK_FREQUENCY(200.0),        // IDELAYCTRL clock input frequency in MHz (190.0-210.0, 290.0-310.0).
                  .SIGNAL_PATTERN("CLOCK")          // DATA, CLOCK input signal
               )
               IDELAYE2_inst (
                  .CNTVALUEOUT(), // 5-bit output: Counter value output
                  .DATAOUT(dqs_in_delayed[i]),         // 1-bit output: Delayed data output
                  .C(1'b0),                     // 1-bit input: Clock input
                  .CE(1'b0),                   // 1-bit input: Active high enable increment/decrement input
                  .CINVCTRL(1'b0),       // 1-bit input: Dynamic clock inversion input
                  .CNTVALUEIN(5'd0),   // 5-bit input: Counter value input
                  .DATAIN(1'b0),           // 1-bit input: Internal delay data input
                  .IDATAIN(dqs_in[i]),         // 1-bit input: Data input from the I/O
                  .INC(1'b0),                 // 1-bit input: Increment / Decrement tap delay input
                  .LD(1'b0),                   // 1-bit input: Load IDELAY_VALUE input
                  .LDPIPEEN(1'b0),       // 1-bit input: Enable PIPELINE register to load data input
                  .REGRST(1'b0)            // 1-bit input: Active-high reset tap-delay input
               );
           end
           
           wire[15:0] dq_in;
           wire[15:0] dq_io_n_wr;
           for (genvar i = 0; i < 16; ++i) begin
               IOBUF #(
                  .IBUF_LOW_PWR("FALSE"),  // Low Power - "TRUE", High Performance = "FALSE" 
                  .IOSTANDARD("SSTL135"), // Specify the I/O standard
                  .SLEW("SLOW")
               ) IOBUF_inst (
                  .O(dq_in[i]),     // Buffer output
                  .IO(ddr3_dq[i]),   // Buffer inout port (connect directly to top-level port)
                  .I(dq_out[i]),     // Buffer input
                  .T(dq_io_n_wr[i])      // 3-state enable input, high=input, low=output
               );
               OSERDESE2 #(
                  .DATA_RATE_OQ("DDR"),   // DDR, SDR
                  .DATA_RATE_TQ("BUF"),   // DDR, BUF, SDR
                  .DATA_WIDTH(8),         // Parallel data width (2-8,10,14)
                  .INIT_OQ(1'b0),         // Initial value of OQ output (1'b0,1'b1)
                  .INIT_TQ(1'b0),         // Initial value of TQ output (1'b0,1'b1)
                  .SERDES_MODE("MASTER"), // MASTER, SLAVE
                  .SRVAL_OQ(1'b0),        // OQ output value when SR is used (1'b0,1'b1)
                  .SRVAL_TQ(1'b0),        // TQ output value when SR is used (1'b0,1'b1)
                  .TBYTE_CTL("FALSE"),    // Enable tristate byte operation (FALSE, TRUE)
                  .TBYTE_SRC("FALSE"),    // Tristate byte source (FALSE, TRUE)
                  .TRISTATE_WIDTH(1)      // 3-state converter width (1,4)
               )
               OSERDESE2_inst (
                  .OFB(),             // 1-bit output: Feedback path for data
                  .OQ(dq_out[i]),               // 1-bit output: Data path output
                  // SHIFTOUT1 / SHIFTOUT2: 1-bit (each) output: Data output expansion (1-bit each)
                  .SHIFTOUT1(),
                  .SHIFTOUT2(),
                  .TBYTEOUT(),   // 1-bit output: Byte group tristate
                  .TFB(),             // 1-bit output: 3-state control
                  .TQ(dq_io_n_wr[i]),               // 1-bit output: 3-state control
                  .CLK(clk_ddr),             // 1-bit input: High speed clock
                  .CLKDIV(clk),       // 1-bit input: Divided clock
                  // D1 - D8: 1-bit (each) input: Parallel data inputs (1-bit each)
                  .D1(wr_data_phy[i]),
                  .D2(wr_data_phy[i]),
                  .D3(wr_data_phy[i]),
                  .D4(wr_data_phy[i]),
                  .D5(wr_data_phy[i + 16]),
                  .D6(wr_data_phy[i + 16]),
                  .D7(wr_data_phy[i + 16]),
                  .D8(wr_data_phy[i + 16]),
                  .OCE(1'b1),             // 1-bit input: Output data clock enable
                  .RST(rst_i),             // 1-bit input: Reset
                  // SHIFTIN1 / SHIFTIN2: 1-bit (each) input: Data input expansion (1-bit each)
                  .SHIFTIN1(1'b0),
                  .SHIFTIN2(1'b0),
                  // T1 - T4: 1-bit (each) input: Parallel 3-state inputs
                  .T1(io_n_wr),
                  .T2(io_n_wr),
                  .T3(io_n_wr),
                  .T4(io_n_wr),
                  .TBYTEIN(1'b0),     // 1-bit input: Byte group tristate
                  .TCE(1'b1)              // 1-bit input: 3-state clock enable
               );
               (* IODELAY_GROUP = "groupinputdelay" *)
               IDELAYE2 #(
                  .CINVCTRL_SEL("FALSE"),          // Enable dynamic clock inversion (FALSE, TRUE)
                  .DELAY_SRC("IDATAIN"),           // Delay input (IDATAIN, DATAIN)
                  .HIGH_PERFORMANCE_MODE("TRUE"), // Reduced jitter ("TRUE"), Reduced power ("FALSE")
                  .IDELAY_TYPE("FIXED"),           // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
                  .IDELAY_VALUE(0),                // Input delay tap setting (0-31)
                  .PIPE_SEL("FALSE"),              // Select pipelined mode, FALSE, TRUE
                  .REFCLK_FREQUENCY(200.0),        // IDELAYCTRL clock input frequency in MHz (190.0-210.0, 290.0-310.0).
                  .SIGNAL_PATTERN("DATA")          // DATA, CLOCK input signal
               )
               IDELAYE2_inst (
                  .CNTVALUEOUT(), // 5-bit output: Counter value output
                  .DATAOUT(dq_in_delayed[i]),         // 1-bit output: Delayed data output
                  .C(1'b0),                     // 1-bit input: Clock input
                  .CE(1'b0),                   // 1-bit input: Active high enable increment/decrement input
                  .CINVCTRL(1'b0),       // 1-bit input: Dynamic clock inversion input
                  .CNTVALUEIN(5'd0),   // 5-bit input: Counter value input
                  .DATAIN(1'b0),           // 1-bit input: Internal delay data input
                  .IDATAIN(dq_in[i]),         // 1-bit input: Data input from the I/O
                  .INC(1'b0),                 // 1-bit input: Increment / Decrement tap delay input
                  .LD(1'b0),                   // 1-bit input: Load IDELAY_VALUE input
                  .LDPIPEEN(1'b0),       // 1-bit input: Enable PIPELINE register to load data input
                  .REGRST(1'b0)            // 1-bit input: Active-high reset tap-delay input
               );
            end
        end
    endgenerate
    
    
    localparam rd_latency = 12;
    reg[rd_latency-1:0] rd_en_q;
    always_ff @(posedge clk) begin
        if (rst_i)
            rd_en_q <= {rd_latency{1'b0}};
        else if (state_q == STATE_READ && !delaying)
            rd_en_q <= {4'b1111, rd_en_q[rd_latency-4:1]};
        else
            rd_en_q <= {1'b0, rd_en_q[rd_latency-1:1]};
    end
    
    wire[15:0] rd_data_phy[3:0];
    
    wire iserde_oclk = clk_ddr;
    wire iserde_clkdiv = clk;
    
    generate begin
            for (genvar i = 0; i < 16; ++i) begin
//                IDDR #(
//                  .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"), // "OPPOSITE_EDGE", "SAME_EDGE" 
//                                                  //    or "SAME_EDGE_PIPELINED" 
//                  .INIT_Q1(1'b0), // Initial value of Q1: 1'b0 or 1'b1
//                  .INIT_Q2(1'b0), // Initial value of Q2: 1'b0 or 1'b1
//                  .SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
//               ) IDDR_inst (
//                  .Q1(rd_data_phy[3][i]), // 1-bit output for positive edge of clock
//                  .Q2(rd_data_phy[0][i]), // 1-bit output for negative edge of clock
//                  .C(dqs_in_delayed[i > 7]),   // 1-bit clock input
//                  .CE(1'b1), // 1-bit clock enable input
//                  .D(dq_in_delayed[i]),   // 1-bit DDR data input
//                  .R(1'b0),   // 1-bit reset
//                  .S(1'b0)    // 1-bit set
//               );
                
                ISERDESE2 #(
                  .DATA_RATE("DDR"),           // DDR, SDR
                  .DATA_WIDTH(4),              // Parallel data width (2-8,10,14)
                  .DYN_CLKDIV_INV_EN("FALSE"), // Enable DYNCLKDIVINVSEL inversion (FALSE, TRUE)
                  .DYN_CLK_INV_EN("FALSE"),    // Enable DYNCLKINVSEL inversion (FALSE, TRUE)
                  // INIT_Q1 - INIT_Q4: Initial value on the Q outputs (0/1)
                  .INIT_Q1(1'b0),
                  .INIT_Q2(1'b0),
                  .INIT_Q3(1'b0),
                  .INIT_Q4(1'b0),
                  .INTERFACE_TYPE("MEMORY"),   // MEMORY, MEMORY_DDR3, MEMORY_QDR, NETWORKING, OVERSAMPLE
                  .IOBDELAY("IFD"),           // NONE, BOTH, IBUF, IFD
                  .NUM_CE(1),                  // Number of clock enables (1,2)
                  .OFB_USED("FALSE"),          // Select OFB path (FALSE, TRUE)
                  .SERDES_MODE("MASTER"),      // MASTER, SLAVE
                  // SRVAL_Q1 - SRVAL_Q4: Q output values when SR is used (0/1)
                  .SRVAL_Q1(1'b0),
                  .SRVAL_Q2(1'b0),
                  .SRVAL_Q3(1'b0),
                  .SRVAL_Q4(1'b0)
               )
               ISERDESE2_inst (
                  .O(),                       // 1-bit output: Combinatorial output
                  // Q1 - Q8: 1-bit (each) output: Registered data outputs
                  .Q1(rd_data_phy[0][i]),
                  .Q2(rd_data_phy[1][i]),
                  .Q3(rd_data_phy[2][i]),
                  .Q4(rd_data_phy[3][i]),
                  .Q5(),
                  .Q6(),
                  .Q7(),
                  .Q8(),
                  // SHIFTOUT1, SHIFTOUT2: 1-bit (each) output: Data width expansion output ports
                  .SHIFTOUT1(),
                  .SHIFTOUT2(),
                  .BITSLIP(1'b0),           // 1-bit input: The BITSLIP pin performs a Bitslip operation synchronous to
                                               // CLKDIV when asserted (active High). Subsequently, the data seen on the Q1
                                               // to Q8 output ports will shift, as in a barrel-shifter operation, one
                                               // position every time Bitslip is invoked (DDR operation is different from
                                               // SDR).
            
                  // CE1, CE2: 1-bit (each) input: Data register clock enable inputs
                  .CE1(1'b1),
                  .CE2(1'b1),
                  .CLKDIVP(1'b0),           // 1-bit input: TBD
                  // Clocks: 1-bit (each) input: ISERDESE2 clock input ports
                  .CLK(dqs_in_delayed[i > 7]),                   // 1-bit input: High-speed clock
                  .CLKB(~dqs_in_delayed[i > 7]),                 // 1-bit input: High-speed secondary clock
                  .CLKDIV(iserde_clkdiv),             // 1-bit input: Divided clock
                  .OCLK(iserde_oclk),                 // 1-bit input: High speed output clock used when INTERFACE_TYPE="MEMORY" 
                  // Dynamic Clock Inversions: 1-bit (each) input: Dynamic clock inversion pins to switch clock polarity
                  .DYNCLKDIVSEL(1'b0), // 1-bit input: Dynamic CLKDIV inversion
                  .DYNCLKSEL(1'b0),       // 1-bit input: Dynamic CLK/CLKB inversion
                  // Input Data: 1-bit (each) input: ISERDESE2 data input ports
                  .D(1'b0),                       // 1-bit input: Data input
                  .DDLY(dq_in_delayed[i]),                 // 1-bit input: Serial data from IDELAYE2
                  .OFB(1'b0),                   // 1-bit input: Data feedback from OSERDESE2
                  .OCLKB(~iserde_oclk),               // 1-bit input: High speed negative edge output clock
                  .RST(rst_i),                   // 1-bit input: Active high asynchronous reset
                  // SHIFTIN1, SHIFTIN2: 1-bit (each) input: Data width expansion input ports
                  .SHIFTIN1(1'b0),
                  .SHIFTIN2(1'b0)
               );
            end
        end
    endgenerate
    reg[127:0] rd_data_q;
    reg rd_last_en = 1'b0;
    always_ff @(posedge clk) begin
        if (rd_en_q[0]) begin
            rd_data_q <= {{rd_data_phy[0], rd_data_phy[3]}, rd_data_q[127:32]};
        end
        rd_last_en <= rd_en_q[0];
        
    end
    assign rd_data = rd_data_q;
    assign rd_data_valid = rd_last_en && !rd_en_q[0];
    
    
    
endmodule
