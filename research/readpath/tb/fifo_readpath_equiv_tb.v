// Cycle-accurate differential check and independent queue reference model.
// Tests reset, full, empty, wrap, simultaneous read/write, and random traffic.
`timescale 1ns/1ps

module fifo_readpath_equiv_tb;
    parameter DATA_WIDTH = 8;
    parameter DEPTH = 16;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg wr_en = 0;
    reg rd_en = 0;
    reg [DATA_WIDTH-1:0] data_in = 0;

    wire [DATA_WIDTH-1:0] baseline_data, alternative_data;
    wire baseline_full, baseline_empty, alternative_full, alternative_empty;

    fifo_sync #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) baseline (
        .clk(clk), .rst(rst), .wr_en(wr_en), .rd_en(rd_en), .data_in(data_in),
        .data_out(baseline_data), .full(baseline_full), .empty(baseline_empty)
    );

    fifo_sync_onehot #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) alternative (
        .clk(clk), .rst(rst), .wr_en(wr_en), .rd_en(rd_en), .data_in(data_in),
        .data_out(alternative_data), .full(alternative_full), .empty(alternative_empty)
    );

    reg [DATA_WIDTH-1:0] queue [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] expected_data = 0;
    reg [63:0] pattern;
    reg accepted_read, accepted_write;
    integer head = 0, tail = 0, items = 0, cycle, seed = 1234567;

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 0;

        for (cycle = 0; cycle < 650; cycle = cycle + 1) begin
            // Fill past full, drain past empty, stress simultaneous operations,
            // then mix burst patterns with deterministic pseudo-random traffic.
            if (cycle < DEPTH + 3) begin
                wr_en = 1; rd_en = 0;
            end else if (cycle < 2 * DEPTH + 6) begin
                wr_en = 0; rd_en = 1;
            end else if (cycle < 3 * DEPTH + 16) begin
                wr_en = 1; rd_en = 1;
            end else if (cycle % 29 == 0) begin
                wr_en = 1; rd_en = 1;
            end else begin
                wr_en = $random(seed);
                rd_en = $random(seed);
            end

            pattern = {$random(seed), $random(seed)};
            data_in = pattern[DATA_WIDTH-1:0];

            accepted_read = rd_en && (items > 0);
            accepted_write = wr_en && ((items < DEPTH) || accepted_read);

            // Always read before overwriting: essential when FIFO is full.
            if (accepted_read) begin
                expected_data = queue[head];
                head = (head + 1) % DEPTH;
            end
            if (accepted_write) begin
                queue[tail] = data_in;
                tail = (tail + 1) % DEPTH;
            end
            if (accepted_write && !accepted_read) items = items + 1;
            if (accepted_read && !accepted_write) items = items - 1;

            @(posedge clk);
            #1;

            if (baseline_full !== (items == DEPTH) ||
                alternative_full !== (items == DEPTH) ||
                baseline_empty !== (items == 0) ||
                alternative_empty !== (items == 0))
                $fatal(1, "full/empty mismatch: cfg=%0dx%0d cycle=%0d items=%0d",
                    DATA_WIDTH, DEPTH, cycle, items);

            if (baseline_data !== expected_data ||
                alternative_data !== expected_data)
                $fatal(1, "data mismatch: cfg=%0dx%0d cycle=%0d expected=%h base=%h alt=%h",
                    DATA_WIDTH, DEPTH, cycle, expected_data, baseline_data, alternative_data);

            @(negedge clk);
        end

        $display("PASS: %0dx%0d, 650 cycles, original and decoder FIFO match independent queue model",
            DATA_WIDTH, DEPTH);
        $finish;
    end
endmodule
