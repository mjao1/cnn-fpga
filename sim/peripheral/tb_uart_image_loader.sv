`timescale 1ns / 1ps

module tb_uart_image_loader;

    localparam int unsigned IMG_BYTES = 784;
    localparam int unsigned ADDR_W = (IMG_BYTES <= 1) ? 1 : $clog2(IMG_BYTES);
    localparam int unsigned BAUD_DIV = 16;
    localparam int CLK_PERIOD = 10;
    localparam real BIT_NS = BAUD_DIV * CLK_PERIOD;

    logic clk;
    logic rst;
    logic rx;
    logic frame_ready;
    logic frame_ack;
    logic [ADDR_W-1:0] ram_raddr;
    logic [7:0] ram_rdata;

    uart_image_loader #(
        .IMG_BYTES(IMG_BYTES),
        .BAUD_DIV(BAUD_DIV)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .frame_ready(frame_ready),
        .frame_ack(frame_ack),
        .ram_rdata(ram_rdata),
        .ram_raddr(ram_raddr)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    task uart_send_async(input logic [7:0] b);
        integer k;
        rx = 1'b0;
        #(BIT_NS);
        for (k = 0; k < 8; k++) begin
            rx = b[k];
            #(BIT_NS);
        end
        rx = 1'b1;
        #(BIT_NS);
    endtask

    task send_image_pattern;
        integer i;
        for (i = 0; i < IMG_BYTES; i++)
            uart_send_async(i[7:0]);
    endtask

    task wait_frame_ready;
        integer n;
        begin : blk
            for (n = 0; n < 50000000; n++) begin
                if (frame_ready === 1'b1)
                    disable blk;
                @(posedge clk);
            end
            $display("FAIL: timeout waiting for frame_ready");
            $finish(1);
        end
    endtask

    task recv_while_sending;
        fork
            send_image_pattern;
            wait_frame_ready;
        join
    endtask

    integer ai, err;

    initial begin
        rst = 1'b1;
        rx  = 1'b1;
        frame_ack = 1'b0;
        ram_raddr = '0;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (10) @(posedge clk);

        recv_while_sending;

        if (!frame_ready) begin
            $display("FAIL: frame_ready not set after transfer");
            $finish(1);
        end

        err = 0;
        for (ai = 0; ai < IMG_BYTES; ai++) begin
            ram_raddr = ADDR_W'(ai);
            #1;
            if (ram_rdata !== ai[7:0])
                err = err + 1;
        end

        if (err !== 0) begin
            $display("FAIL: %0d RAM mismatches", err);
            $finish(1);
        end

        @(posedge clk);
        frame_ack = 1'b1;
        @(posedge clk);
        frame_ack = 1'b0;

        if (frame_ready !== 1'b0) begin
            $display("FAIL: frame_ack did not clear frame_ready");
            $finish(1);
        end

        $display("PASS: (%0d bytes)", IMG_BYTES);
        $finish(0);
    end

endmodule
