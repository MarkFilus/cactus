module top #(
    parameter integer LED_BIT = 23
) (
    input  wire CLK,
    input  wire RX,
    output wire LEDR_N,
    output wire TX
);
    reg [3:0] reset_count = 0;
    wire rst_n = &reset_count;
    wire [23:0] count;

    always @(posedge CLK) begin
        if (!rst_n)
            reset_count <= reset_count + 1'b1;
    end

    vhdl_counter counter_i (
        .clk(CLK),
        .rst_n(rst_n),
        .count(count)
    );

    uart_challenge #(
        .CLK_HZ(12000000),
        .BAUD(115200)
    ) uart_i (
        .clk(CLK),
        .rst_n(rst_n),
        .rx(RX),
        .tx(TX)
    );

    assign LEDR_N = ~count[LED_BIT];
endmodule
