// Receives a fixed-length image over UART (8-bit pixels) into on-chip RAM.

module uart_image_loader #(
    parameter int unsigned IMG_BYTES = 784,
    parameter int unsigned ADDR_W = (IMG_BYTES <= 1) ? 1 : $clog2(IMG_BYTES),
    parameter int unsigned BAUD_DIV = 868
)(
    input  logic              clk_i,
    input  logic              rst_i,
    input  logic              rx_i,
    input  logic              frame_ack_i,
    input  logic [ADDR_W-1:0] ram_raddr_i,
    output logic              frame_ready_o,
    output logic [7:0]        ram_rdata_o
);

    logic [7:0] mem [0:IMG_BYTES-1];
    logic [ADDR_W-1:0] wr_idx;

    logic [7:0] uart_data;
    logic uart_valid;

    uart_rx #(
        .BAUD_DIV(BAUD_DIV)
    ) u_uart_rx (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .rx_i(rx_i),
        .data_o(uart_data),
        .valid_o(uart_valid)
    );

    assign ram_rdata_o = mem[ram_raddr_i];

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            wr_idx <= '0;
            frame_ready_o <= 1'b0;
        end else begin
            if (frame_ack_i) begin
                frame_ready_o <= 1'b0;
                wr_idx <= '0;
            end else if (uart_valid && !frame_ready_o) begin
                mem[wr_idx] <= uart_data;
                if (wr_idx == IMG_BYTES - 1)
                    frame_ready_o <= 1'b1;
                else
                    wr_idx <= wr_idx + 1'b1;
            end
        end
    end

endmodule
