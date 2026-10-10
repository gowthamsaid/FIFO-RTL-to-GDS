`timescale 1ns/1ps

module fifo_sync_tb;

    reg clk = 0;
    reg rst = 1;
    reg wr_en = 0;
    reg rd_en = 0;

    reg [7:0] data_in = 0;
    wire [7:0] data_out;
    wire full, empty;

    // Generate a 10 ns clock
    always #5 clk = ~clk;

    // Instantiate our FIFO
    fifo_sync #(
        .DATA_WIDTH(8),
        .DEPTH(16)
    ) dut (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .data_in(data_in),
        .data_out(data_out),
        .full(full),
        .empty(empty)
    );

    initial begin

        // Check reset
        @(posedge clk);
        #1;
        if (!empty || full)
            $fatal(1, "Reset failed");

        // Write first value
        @(negedge clk);
        rst = 0;
        wr_en = 1;
        data_in = 8'hA5;

        @(posedge clk);
        #1;
        if (empty)
            $fatal(1, "Write failed");

        // Write second value
        @(negedge clk);
        data_in = 8'h3C;

        @(posedge clk);
        #1;

        // Read first value
        @(negedge clk);
        wr_en = 0;
        rd_en = 1;

        @(posedge clk);
        #1;
        if (data_out !== 8'hA5)
            $fatal(1, "First read failed");

        // Read second value
        @(posedge clk);
        #1;
        if (data_out !== 8'h3C || !empty)
            $fatal(1, "Second read failed");

        $display("PASS: FIFO basic read/write test");
        $finish;

    end

endmodule
