`default_nettype none
`timescale 1ns / 1ps

/*
 * Testbench wrapper for Keropiyo Tiny AM Radio.
 *
 * This module connects the Tiny Tapeout project to cocotb test.py.
 */

module tb ();

    // Dump signals for GTKWave or Surfer.
    initial begin
        $dumpfile("tb.fst");
        $dumpvars(0, tb);
        #1;
    end

    // Tiny Tapeout inputs
    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    reg [7:0] uio_in;

    // Tiny Tapeout outputs
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

`ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
`endif

    // Instantiate the Keropiyo AM radio.
    tt_um_keropiyo_am_radio user_project (

`ifdef GL_TEST
        .VPWR   (VPWR),
        .VGND   (VGND),
`endif

        .ui_in  (ui_in),
        .uo_out (uo_out),
        .uio_in (uio_in),
        .uio_out(uio_out),
        .uio_oe (uio_oe),
        .ena    (ena),
        .clk    (clk),
        .rst_n  (rst_n)
    );

endmodule

`default_nettype wire
