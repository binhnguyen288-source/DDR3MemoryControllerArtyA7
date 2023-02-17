`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/04/2023 01:19:06 AM
// Design Name: 
// Module Name: testbench
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


module testbench();
    reg osc = 1'b0;
    always #5 osc = ~osc;
    wire          ddr3_cke_w;
    wire          ddr3_reset_n_w;
    wire          ddr3_ras_n_w;
    wire          ddr3_cas_n_w;
    wire          ddr3_we_n_w;
    wire          ddr3_cs_n_w;
    wire [  2:0]  ddr3_ba_w;
    wire [ 13:0]  ddr3_addr_w;
    wire          ddr3_odt_w;
    wire [  1:0]  ddr3_dm_w;
    wire [ 15:0]  ddr3_dq_w;
    wire          ddr3_ck_p_w;
    wire          ddr3_ck_n_w;
    wire [  1:0]  ddr3_dqs_p_w;
    wire [  1:0]  ddr3_dqs_n_w;
    
    ddr3
    u_ram
    (
         .rst_n(ddr3_reset_n_w)
        ,.ck(ddr3_ck_p_w)
        ,.ck_n(ddr3_ck_n_w)
        ,.cke(ddr3_cke_w)
        ,.cs_n(ddr3_cs_n_w)
        ,.ras_n(ddr3_ras_n_w)
        ,.cas_n(ddr3_cas_n_w)
        ,.we_n(ddr3_we_n_w)
        ,.dm_tdqs(ddr3_dm_w)
        ,.ba(ddr3_ba_w)
        ,.addr(ddr3_addr_w)
        ,.dq(ddr3_dq_w)
        ,.dqs(ddr3_dqs_p_w)
        ,.dqs_n(ddr3_dqs_n_w)
        ,.tdqs_n()
        ,.odt(ddr3_odt_w)
    );
    wire[3:0] led;
    top inst(
        .osc(osc)
        ,.ddr3_reset_n(ddr3_reset_n_w)
        ,.ddr3_ck_p(ddr3_ck_p_w)
        ,.ddr3_ck_n(ddr3_ck_n_w)
        ,.ddr3_cke(ddr3_cke_w)
        ,.ddr3_cs_n(ddr3_cs_n_w)
        ,.ddr3_ras_n(ddr3_ras_n_w)
        ,.ddr3_cas_n(ddr3_cas_n_w)
        ,.ddr3_we_n(ddr3_we_n_w)
        ,.ddr3_dm(ddr3_dm_w)
        ,.ddr3_ba(ddr3_ba_w)
        ,.ddr3_addr(ddr3_addr_w)
        ,.ddr3_dq(ddr3_dq_w)
        ,.ddr3_dqs_p(ddr3_dqs_p_w)
        ,.ddr3_dqs_n(ddr3_dqs_n_w)
        ,.ddr3_odt(ddr3_odt_w)
        ,.led(led)
    );
    always @(posedge osc) begin
        if (led !== 4'hf) $fatal(1, "error detected");
    end
    
endmodule
