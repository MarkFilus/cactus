module tb;
    localparam integer BIT_CYCLES = 104;
    logic CLK = 0;
    logic RX = 1;
    wire LEDR_N;
    wire TX;
    integer i;
    reg [7:0] observed [0:26];
    reg led_toggled = 0;
    reg monitor_led = 0;

    top #(.LED_BIT(7)) dut (
        .CLK(CLK),
        .RX(RX),
        .LEDR_N(LEDR_N),
        .TX(TX)
    );

    always #5 CLK = ~CLK;
    always @(LEDR_N) begin
        if (monitor_led)
            led_toggled = 1;
    end

    task automatic send_byte(input reg [7:0] value);
        integer bit_no;
        begin
            RX = 1'b0;
            repeat (BIT_CYCLES) @(posedge CLK);
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                RX = value[bit_no];
                repeat (BIT_CYCLES) @(posedge CLK);
            end
            RX = 1'b1;
            repeat (BIT_CYCLES) @(posedge CLK);
        end
    endtask

    task automatic receive_byte(output reg [7:0] value);
        integer bit_no;
        begin
            @(negedge TX);
            repeat (BIT_CYCLES + BIT_CYCLES/2) @(posedge CLK);
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                value[bit_no] = TX;
                repeat (BIT_CYCLES) @(posedge CLK);
            end
            if (TX !== 1'b1)
                $fatal(1, "UART stop bit was not high");
        end
    endtask

    function automatic reg [7:0] expected_byte(input integer index);
        begin
            case (index)
                0: expected_byte = "G";
                1: expected_byte = "A";
                2: expected_byte = "T";
                3: expected_byte = "E";
                4: expected_byte = "L";
                5: expected_byte = "I";
                6: expected_byte = "N";
                7: expected_byte = "T";
                8: expected_byte = " ";
                9: expected_byte = "0";
                10: expected_byte = "1";
                11: expected_byte = "2";
                12: expected_byte = "3";
                13: expected_byte = "4";
                14: expected_byte = "5";
                15: expected_byte = "6";
                16: expected_byte = "7";
                17: expected_byte = " ";
                18: expected_byte = "3";
                19: expected_byte = "4";
                20: expected_byte = "6";
                21: expected_byte = "1";
                22: expected_byte = "2";
                23: expected_byte = "D";
                24: expected_byte = "F";
                25: expected_byte = "1";
                default: expected_byte = 8'h0a;
            endcase
        end
    endfunction

    task automatic send_challenge;
        begin
            send_byte("?");
            send_byte("0");
            send_byte("1");
            send_byte("2");
            send_byte("3");
            send_byte("4");
            send_byte("5");
            send_byte("6");
            send_byte("7");
            send_byte(8'h0a);
        end
    endtask

    initial begin
        repeat (30) @(posedge CLK);
        monitor_led = 1;
        fork
            begin
                for (i = 0; i < 27; i = i + 1)
                    receive_byte(observed[i]);
            end
            begin
                send_challenge();
            end
        join
        for (i = 0; i < 27; i = i + 1) begin
            if (observed[i] != expected_byte(i))
                $fatal(1, "UART challenge response mismatch at byte %0d: got %02x expected %02x", i, observed[i], expected_byte(i));
        end
        if (!led_toggled)
            $fatal(1, "VHDL counter did not toggle the LED path");
        $display("GATELINT_SIM_PASS");
        $finish;
    end

    initial begin
        repeat (100000) @(posedge CLK);
        $fatal(1, "simulation timeout");
    end
endmodule
