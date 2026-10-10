`timescale 1ns/1ps

module register_demo_tb;

reg clk = 0;
reg rst = 1;
reg [7:0] d = 0;
wire [7:0] q;

register_demo dut (
    .clk(clk),
    .rst(rst),
    .d(d),
    .q(q)
);

// Clock period = 10 ns
always #5 clk = ~clk;

initial begin
    #12;

    if (q !== 8'h00)
        $fatal(1, "Reset test failed");

    rst = 0;
    d = 8'hA5;

    #10;

    if (q !== 8'hA5)
        $fatal(1, "First data test failed");

    d = 8'h3C;

    #10;

    if (q !== 8'h3C)
        $fatal(1, "Second data test failed");

    $display("PASS: Clocked register simulation");
    $finish;
end

endmodule
