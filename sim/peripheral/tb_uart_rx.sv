`timescale 1ns / 1ps

module tb_uart_rx;

    parameter int unsigned BAUD_DIV = 32;
    parameter int CLK_PERIOD = 10;
    parameter real BIT_NS = BAUD_DIV * CLK_PERIOD;

    logic clk;
    logic rst;
    logic rx;
    logic [7:0] data;
    logic valid;

    uart_rx #(
        .BAUD_DIV(BAUD_DIV)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .data(data),
        .valid(valid)
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

    task wait_rx_byte(input logic [7:0] expected);
        integer n;
        begin : rx_done
            for (n = 0; n < 500000; n++) begin
                if (valid === 1'b1) begin
                    if (data !== expected) begin
                        $display("FAIL: expected %h got %h", expected, data);
                        $finish(1);
                    end
                    disable rx_done;
                end
                @(posedge clk);
            end
            $display("FAIL: timeout waiting for valid");
            $finish(1);
        end
    endtask

    task send_and_check(input logic [7:0] expected);
        fork
            uart_send_async(expected);
            wait_rx_byte(expected);
        join
        $display("PASS: received %h", data);
    endtask

    initial begin
        rst = 1'b1;
        rx  = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (50) @(posedge clk);

        send_and_check(8'hA5);
        repeat (100) @(posedge clk);
        send_and_check(8'h00);
        repeat (100) @(posedge clk);
        send_and_check(8'hFF);

        $finish(0);
    end

endmodule
