`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/08/2023 01:42:23 AM
// Design Name: 
// Module Name: top
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


module top(
    input osc,
    output ddr3_reset_n,
    output ddr3_cke,
    output ddr3_ck_p,
    output ddr3_ck_n,
    output ddr3_cs_n,
    output ddr3_ras_n,
    output ddr3_cas_n,
    output ddr3_we_n,
    output[2:0] ddr3_ba,
    output[13:0] ddr3_addr,
    output ddr3_odt,
    output[1:0] ddr3_dm,
    inout[1:0] ddr3_dqs_p,
    inout[1:0] ddr3_dqs_n,
    inout[15:0] ddr3_dq,
    output[3:0] led
);
    wire pll_locked;
    wire clk, clk_90, clk_ref, clk_ddr;
   clkgen clkgeninst(
    .osc(osc),
    .clk(clk),
    .clk_90(clk_90),
    .clk_ref(clk_ref),
    .clk_ddr(clk_ddr),
    .pll_locked(pll_locked)
   );
   reg rst_i = 1'b1;
   reg[3:0] rst_counter = 4'h0;
   always_ff @(posedge clk) begin
    if (&rst_counter)
        rst_i <= 1'b0;
    else if (pll_locked)
        rst_counter <= rst_counter + 1;
    else 
        rst_counter <= 4'h0;
   end
   
   reg[31:0]    ram_addr;
   reg          ram_wr;
   reg[127:0]   ram_wr_data;
   reg          ram_rd;
   wire[127:0]  ram_rd_data;
   wire         ram_accept;
   wire         ram_ack;
   assign ddr3_cs_n = 1'b0;
   
   ddr3_controller controller(
    // user ports
    .rst_i(rst_i),
    .clk(clk),
    .clk_90(clk_90),
    .clk_ref(clk_ref),
    .clk_ddr(clk_ddr),
    .ram_addr(ram_addr),
    .wr_en(ram_wr),
    .wr_data(ram_wr_data),
    .rd_en(ram_rd),
    .rd_data(ram_rd_data),
    .accepted(ram_accept),
    .acked(ram_ack),
    // io ports
    .ddr3_reset_n(ddr3_reset_n),
    .ddr3_cke(ddr3_cke),
    .ddr3_ck_p(ddr3_ck_p),
    .ddr3_ck_n(ddr3_ck_n),
    .ddr3_ras_n(ddr3_ras_n),
    .ddr3_cas_n(ddr3_cas_n),
    .ddr3_we_n(ddr3_we_n),
    .ddr3_ba(ddr3_ba),
    .ddr3_addr(ddr3_addr),
    .ddr3_odt(ddr3_odt),
    .ddr3_dm(ddr3_dm),
    .ddr3_dqs_p(ddr3_dqs_p),
    .ddr3_dqs_n(ddr3_dqs_n),
    .ddr3_dq(ddr3_dq)
   );
   typedef enum {
        START_WRITE, WRITING, WRITE_DONE,
        START_READ, READING, DONE_READ,
        FINISH, INVALID
    } TEST_STATE;
     
    TEST_STATE state_q = INVALID;
    reg[127:0] read_result = 128'h0;
    reg[3:0] error_count = 4'h0;
    
    
    reg[31:0] data_valid = '0;
    reg[127:0] written_data[31:0];
    initial begin
        for (int i = 0; i < 32; ++i)
            written_data[i] <= '0;
    end
    
    reg[127:0]  test_data = 128'h1234567890987654321abcdef7283791;
    wire[127:0] next_random = test_data ^ {test_data[126:0], test_data[127]};
    wire[31:0]  test_addr = {23'h0, test_data[8:4], 4'h0};
    
    always_ff @(posedge clk) begin
        if (rst_i) begin
            state_q        <= START_WRITE;
            ram_wr         <= 1'b0;
            ram_rd         <= 1'b0;
            error_count    <= 4'h0;
        end else begin
            case (state_q)
                START_WRITE: begin
                    ram_wr         <= 1'b1;
                    ram_addr       <= test_addr;
                    ram_wr_data    <= test_data;
                    state_q        <= WRITING;
                    data_valid[test_addr[8:4]]   <= 1'b1;
                    written_data[test_addr[8:4]] <= test_data;
                end
                WRITING: begin
                    if (ram_accept) begin
                        ram_wr  <= 1'b0;
                        state_q <= WRITE_DONE;
                    end
                end
                WRITE_DONE: begin
                    if (ram_ack) begin
                        
                        state_q <= test_data[0] ? START_WRITE : START_READ;
                        test_data <= next_random;
                    end
                end
                START_READ: begin
                    ram_addr <= test_addr;
                    state_q  <= READING;
                    ram_rd <= 1'b1;
                end
                READING: begin
                    if (ram_accept) begin
                        ram_rd <= 1'b0;
                        state_q <= DONE_READ;
                    end
                end
                DONE_READ: begin
                    if (ram_ack) begin
                        read_result <= ram_rd_data;
                        state_q <= FINISH;
                    end
                end
                FINISH: begin
                        if (read_result != written_data[test_addr[8:4]] && data_valid[test_addr[8:4]]) begin
                            error_count <= error_count == 4'hf ? 4'hf : error_count + 1;
                        end
                        state_q <= test_data[0] ? START_WRITE : START_READ;
                        test_data <= next_random;
                end
                default:;
            endcase
        end
    end
    assign led = ~error_count;
   
   
    
endmodule
