// Research pilot: functional match for fifo_sync with alternative read select.
// Difference from baseline: shared address decoder followed by an AND/OR
// selection network, rather than inferred binary indexed-read mux.
// This RTL is a hypothesis, not a claim of better area or timing.
// Intended supported DEPTH values: powers of two (>=2).
`timescale 1ns/1ps

module fifo_sync_onehot #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 16
)(
    input wire clk,
    input wire rst,
    input wire wr_en,
    input wire rd_en,
    input wire [DATA_WIDTH-1:0] data_in,
    output reg [DATA_WIDTH-1:0] data_out,
    output wire full,
    output wire empty
);

    localparam PTR_WIDTH = $clog2(DEPTH);
    localparam COUNT_WIDTH = $clog2(DEPTH + 1);

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [PTR_WIDTH-1:0] read_ptr;
    reg [PTR_WIDTH-1:0] write_ptr;
    reg [COUNT_WIDTH-1:0] count;

    assign full = (count == DEPTH);
    assign empty = (count == 0);

    wire read_accept = rd_en && !empty;
    wire write_accept = wr_en && (!full || read_accept);

    // Decode the address once, share the one-hot term across every data bit.
    wire [DEPTH-1:0] read_select;
    genvar entry, bit_index;
    generate
        for (entry = 0; entry < DEPTH; entry = entry + 1) begin : gen_decode
            assign read_select[entry] = (read_ptr == entry);
        end
    endgenerate

    wire [DATA_WIDTH-1:0] selected_data;
    generate
        for (bit_index = 0; bit_index < DATA_WIDTH; bit_index = bit_index + 1) begin : gen_data_bit
            wire [DEPTH-1:0] terms;
            for (entry = 0; entry < DEPTH; entry = entry + 1) begin : gen_term
                assign terms[entry] = memory[entry][bit_index] & read_select[entry];
            end
            assign selected_data[bit_index] = |terms;
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            read_ptr <= 0;
            write_ptr <= 0;
            count <= 0;
            data_out <= 0;
        end else begin
            if (read_accept) begin
                data_out <= selected_data;
                read_ptr <= read_ptr + 1'b1;
            end

            if (write_accept) begin
                memory[write_ptr] <= data_in;
                write_ptr <= write_ptr + 1'b1;
            end

            if (write_accept && !read_accept)
                count <= count + 1'b1;
            else if (read_accept && !write_accept)
                count <= count - 1'b1;
        end
    end
endmodule
