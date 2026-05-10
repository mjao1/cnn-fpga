// Receives a fixed-length image over UART (8-bit pixels) into on-chip RAM.

module uart_image_loader #(
    parameter int unsigned IMG_BYTES = 784,
    parameter int unsigned ADDR_W = (IMG_BYTES <= 1) ? 1 : $clog2(IMG_BYTES),
    parameter int unsigned BAUD_DIV = 868
)(
    input logic clk,
    input logic rst,
    input logic rx,
    output logic frame_ready,
    input logic frame_ack,
    output logic [7:0] ram_rdata,
    input logic [ADDR_W-1:0] ram_raddr
);

    logic [7:0] mem [0:IMG_BYTES-1];
    logic [ADDR_W-1:0] wr_idx;

    logic [7:0] uart_data;
    logic uart_valid;

    uart_rx #(
        .BAUD_DIV(BAUD_DIV)
    ) u_uart_rx (
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .data(uart_data),
        .valid(uart_valid)
    );

    assign ram_rdata = mem[ram_raddr];

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_idx <= '0;
            frame_ready <= 1'b0;
        end else begin
            if (frame_ack) begin
                frame_ready <= 1'b0;
                wr_idx <= '0;
            end else if (uart_valid && !frame_ready) begin
                mem[wr_idx] <= uart_data;
                if (wr_idx == IMG_BYTES - 1)
                    frame_ready <= 1'b1;
                else
                    wr_idx <= wr_idx + 1'b1;
            end
        end
    end

endmodule
