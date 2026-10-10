`timescale 1ns/1ps

module fifo_sync #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 16
)(
    input  wire clk,
    input  wire rst,

    input  wire wr_en,
    input  wire rd_en,

    input  wire [DATA_WIDTH-1:0] data_in,
    output reg  [DATA_WIDTH-1:0] data_out,

    output wire full,
    output wire empty
);

    // Calculate register widths
    localparam PTR_WIDTH = $clog2(DEPTH);
    localparam COUNT_WIDTH = $clog2(DEPTH + 1);

    // FIFO memory array
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    // Read and write pointers
    reg [PTR_WIDTH-1:0] read_ptr;
    reg [PTR_WIDTH-1:0] write_ptr;

    // Number of valid entries
    reg [COUNT_WIDTH-1:0] count;

    // Full and empty flags
    assign full  = (count == DEPTH);
    assign empty = (count == 0);

    // Read and write acceptance signals
    wire read_accept;
    wire write_accept;

    assign read_accept = rd_en && !empty;
    assign write_accept = wr_en && (!full || read_accept);

    // Sequential FIFO logic
    always @(posedge clk) begin

        if (rst) begin
            read_ptr  <= 0;
            write_ptr <= 0;
            count     <= 0;
            data_out  <= 0;
        end

        else begin

            // READ operation
            if (read_accept) begin
                data_out <= memory[read_ptr];
                read_ptr <= read_ptr + 1'b1;
            end

            // WRITE operation
            if (write_accept) begin
                memory[write_ptr] <= data_in;
                write_ptr <= write_ptr + 1'b1;
            end

            // Occupancy counter update
            if (write_accept && !read_accept)
                count <= count + 1'b1;

            else if (read_accept && !write_accept)
                count <= count - 1'b1;

        end
    end

endmodule
