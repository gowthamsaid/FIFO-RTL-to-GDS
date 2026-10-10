`timescale 1ns/1ps

module fifo_boundary_tb #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 16
);

    reg clk = 0;
    reg rst = 1;
    reg wr_en = 0;
    reg rd_en = 0;

    reg [DATA_WIDTH-1:0] data_in = 0;
    wire [DATA_WIDTH-1:0] data_out;
    wire full, empty;

    integer i;

    always #5 clk = ~clk;

    fifo_sync #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
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

        // Verify reset state
        @(posedge clk);
        #1;
        if (!empty || full)
            $fatal(1, "Reset test failed");

        // Fill the FIFO
        @(negedge clk);
        rst = 0;

        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge clk);
            wr_en = 1;
            data_in = i + 1;

            @(posedge clk);
            #1;
        end

        if (!full || empty)
            $fatal(1, "Full flag test failed");

        // Attempt overflow
        @(negedge clk);
        data_in = 'hEE;

        @(posedge clk);
        #1;

        if (!full)
            $fatal(1, "Overflow protection failed");

        // Drain the FIFO and verify ordering
        @(negedge clk);
        wr_en = 0;
        rd_en = 1;

        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk);
            #1;

            if (data_out !== (i + 1))
                $fatal(1, "FIFO data mismatch at %0d", i);
        end

        if (!empty || full)
            $fatal(1, "Empty flag test failed");

        // Attempt underflow
        @(posedge clk);
        #1;

        if (!empty || data_out !== DEPTH)
            $fatal(1, "Underflow protection failed");

        $display("PASS: FIFO boundary test, width=%0d depth=%0d",
                 DATA_WIDTH, DEPTH);

        $finish;
    end

endmodule
