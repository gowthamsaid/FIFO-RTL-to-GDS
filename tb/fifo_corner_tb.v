`timescale 1ns/1ps

module fifo_corner_tb #(
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

    reg [DATA_WIDTH-1:0] model [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] expected_out = 0;

    integer used = 0;
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

    // Apply one clock-cycle transaction
    task automatic run_cycle;
        input wreq;
        input rreq;
        input [DATA_WIDTH-1:0] value;

        reg take_read;
        reg take_write;
        integer j;

        begin
            @(negedge clk);

            rst = 0;
            wr_en = wreq;
            rd_en = rreq;
            data_in = value;

            // Independent reference model
            take_read = rreq && (used > 0);
            take_write = wreq &&
                         ((used < DEPTH) || take_read);

            if (take_read) begin
                expected_out = model[0];

                for (j = 0; j < used-1; j = j+1)
                    model[j] = model[j+1];

                used = used - 1;
            end

            if (take_write) begin
                model[used] = value;
                used = used + 1;
            end

            @(posedge clk);
            #1;

            if (full !== (used == DEPTH))
                $fatal(1, "Full flag mismatch");

            if (empty !== (used == 0))
                $fatal(1, "Empty flag mismatch");

            if (data_out !== expected_out)
                $fatal(1, "Data mismatch: expected %h, got %h",
                       expected_out, data_out);
        end
    endtask

    initial begin

        // Reset test
        @(posedge clk);
        #1;

        if (!empty || full || data_out !== 0)
            $fatal(1, "Reset failed");

        // Test 1: Fill FIFO completely
        for (i = 0; i < DEPTH; i = i+1)
            run_cycle(1, 0, i+100);

        // Test 2: Simultaneous operation when full
        run_cycle(1, 1, 'hE1);

        // Drain and check ordering
        for (i = 0; i < DEPTH; i = i+1)
            run_cycle(0, 1, 0);

        // Test 3: Simultaneous requests when empty
        run_cycle(1, 1, 'hD2);
        run_cycle(0, 1, 0);

        // Test 4: Repeated pointer wraparound
        for (i = 0; i < DEPTH*3+5; i = i+1) begin
            run_cycle(1, 0, i+1);
            run_cycle(0, 1, 0);
        end

        // Test 5: Simultaneous traffic while partially full
        run_cycle(1, 0, 'h11);
        run_cycle(1, 0, 'h22);
        run_cycle(1, 0, 'h33);
        run_cycle(1, 1, 'h44);

        run_cycle(0, 1, 0);
        run_cycle(0, 1, 0);
        run_cycle(0, 1, 0);

        $display("PASS: FIFO corner tests, width=%0d depth=%0d",
                 DATA_WIDTH, DEPTH);

        $finish;
    end

endmodule
