module uart_challenge #(
    parameter integer CLK_HZ = 12000000,
    parameter integer BAUD = 115200
) (
    input  logic clk,
    input  logic rst_n,
    input  logic rx,
    output logic tx
);
    localparam integer DIVISOR = (CLK_HZ + BAUD/2) / BAUD;
    localparam logic [31:0] RESPONSE_XOR = 32'hA5C39E71;

    localparam logic [1:0] PARSER_WAIT_START = 2'd0;
    localparam logic [1:0] PARSER_HEX        = 2'd1;
    localparam logic [1:0] PARSER_WAIT_EOL   = 2'd2;

    logic rx_meta = 1'b1;
    logic rx_sync = 1'b1;
    logic rx_busy = 1'b0;
    logic [15:0] rx_count = 0;
    logic [3:0] rx_bit_index = 0;
    logic [7:0] rx_shift = 0;
    logic [7:0] rx_byte = 0;
    logic rx_valid = 1'b0;

    logic [1:0] parser_state = PARSER_WAIT_START;
    logic [3:0] nibble_count = 0;
    logic [31:0] challenge_shift = 0;
    logic [31:0] response_challenge = 0;
    logic [31:0] response_value = 0;
    logic response_valid = 1'b0;

    logic tx_busy = 1'b0;
    logic message_active = 1'b0;
    logic [15:0] tx_count = 0;
    logic [3:0] tx_bit_index = 0;
    logic [9:0] tx_shift = 10'h3ff;
    logic [4:0] char_index = 0;
    logic [31:0] tx_challenge = 0;
    logic [31:0] tx_response = 0;

    function automatic logic is_hex(input logic [7:0] value);
        begin
            is_hex = ((value >= "0") && (value <= "9")) ||
                     ((value >= "A") && (value <= "F")) ||
                     ((value >= "a") && (value <= "f"));
        end
    endfunction

    function automatic logic [3:0] hex_value(input logic [7:0] value);
        begin
            if ((value >= "0") && (value <= "9"))
                hex_value = value - "0";
            else if ((value >= "A") && (value <= "F"))
                hex_value = value - "A" + 4'd10;
            else
                hex_value = value - "a" + 4'd10;
        end
    endfunction

    function automatic logic [7:0] hex_char(input logic [3:0] value);
        begin
            if (value < 10)
                hex_char = "0" + value;
            else
                hex_char = "A" + (value - 10);
        end
    endfunction

    function automatic logic [3:0] word_nibble(
        input logic [31:0] word,
        input logic [2:0] index
    );
        begin
            case (index)
                0: word_nibble = word[31:28];
                1: word_nibble = word[27:24];
                2: word_nibble = word[23:20];
                3: word_nibble = word[19:16];
                4: word_nibble = word[15:12];
                5: word_nibble = word[11:8];
                6: word_nibble = word[7:4];
                default: word_nibble = word[3:0];
            endcase
        end
    endfunction

    function automatic logic [31:0] challenge_response(input logic [31:0] value);
        begin
            challenge_response = {value[24:0], value[31:25]} ^ RESPONSE_XOR;
        end
    endfunction

    function automatic logic [7:0] message_byte(
        input logic [4:0] index,
        input logic [31:0] challenge,
        input logic [31:0] response
    );
        begin
            case (index)
                0: message_byte = "G";
                1: message_byte = "A";
                2: message_byte = "T";
                3: message_byte = "E";
                4: message_byte = "L";
                5: message_byte = "I";
                6: message_byte = "N";
                7: message_byte = "T";
                8: message_byte = " ";
                9, 10, 11, 12, 13, 14, 15, 16:
                    message_byte = hex_char(word_nibble(challenge, index - 9));
                17: message_byte = " ";
                18, 19, 20, 21, 22, 23, 24, 25:
                    message_byte = hex_char(word_nibble(response, index - 18));
                default: message_byte = 8'h0a;
            endcase
        end
    endfunction

    // Two-flop synchronization plus an 8N1 receiver. The first sample occurs
    // at the middle of the start bit, followed by one sample per data bit.
    always_ff @(posedge clk) begin
        rx_meta <= rx;
        rx_sync <= rx_meta;
        rx_valid <= 1'b0;

        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_busy <= 1'b0;
            rx_count <= 0;
            rx_bit_index <= 0;
            rx_shift <= 0;
            rx_byte <= 0;
        end else if (!rx_busy) begin
            if (!rx_sync) begin
                rx_busy <= 1'b1;
                rx_count <= DIVISOR/2 - 1;
                rx_bit_index <= 0;
            end
        end else if (rx_count != 0) begin
            rx_count <= rx_count - 1'b1;
        end else begin
            case (rx_bit_index)
                0: begin
                    if (rx_sync) begin
                        rx_busy <= 1'b0;
                    end else begin
                        rx_bit_index <= 1;
                        rx_count <= DIVISOR - 1;
                    end
                end
                1, 2, 3, 4, 5, 6, 7, 8: begin
                    rx_shift[rx_bit_index-1] <= rx_sync;
                    rx_bit_index <= rx_bit_index + 1'b1;
                    rx_count <= DIVISOR - 1;
                end
                default: begin
                    rx_busy <= 1'b0;
                    if (rx_sync) begin
                        rx_byte <= rx_shift;
                        rx_valid <= 1'b1;
                    end
                end
            endcase
        end
    end

    // Parse ?XXXXXXXX\n and emit a one-cycle response request. A malformed
    // frame is discarded and cannot accidentally satisfy the host proof.
    always_ff @(posedge clk) begin
        response_valid <= 1'b0;
        if (!rst_n) begin
            parser_state <= PARSER_WAIT_START;
            nibble_count <= 0;
            challenge_shift <= 0;
            response_challenge <= 0;
            response_value <= 0;
        end else if (rx_valid) begin
            case (parser_state)
                PARSER_WAIT_START: begin
                    if (rx_byte == "?") begin
                        parser_state <= PARSER_HEX;
                        nibble_count <= 0;
                        challenge_shift <= 0;
                    end
                end
                PARSER_HEX: begin
                    if (is_hex(rx_byte)) begin
                        challenge_shift <= {challenge_shift[27:0], hex_value(rx_byte)};
                        if (nibble_count == 7)
                            parser_state <= PARSER_WAIT_EOL;
                        else
                            nibble_count <= nibble_count + 1'b1;
                    end else if (rx_byte == "?") begin
                        nibble_count <= 0;
                        challenge_shift <= 0;
                    end else begin
                        parser_state <= PARSER_WAIT_START;
                    end
                end
                default: begin
                    if (rx_byte == 8'h0a) begin
                        response_challenge <= challenge_shift;
                        response_value <= challenge_response(challenge_shift);
                        response_valid <= 1'b1;
                        parser_state <= PARSER_WAIT_START;
                    end else if (rx_byte == 8'h0d) begin
                        parser_state <= PARSER_WAIT_EOL;
                    end else if (rx_byte == "?") begin
                        parser_state <= PARSER_HEX;
                        nibble_count <= 0;
                        challenge_shift <= 0;
                    end else begin
                        parser_state <= PARSER_WAIT_START;
                    end
                end
            endcase
        end
    end

    // Transmit GATELINT XXXXXXXX YYYYYYYY\n, where Y is bound to X by the
    // same transform used by the host verifier.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            tx <= 1'b1;
            tx_busy <= 1'b0;
            message_active <= 1'b0;
            tx_count <= 0;
            tx_bit_index <= 0;
            tx_shift <= 10'h3ff;
            char_index <= 0;
            tx_challenge <= 0;
            tx_response <= 0;
        end else begin
            if (response_valid && !message_active && !tx_busy) begin
                message_active <= 1'b1;
                char_index <= 0;
                tx_challenge <= response_challenge;
                tx_response <= response_value;
            end

            if (tx_busy) begin
                if (tx_count != 0) begin
                    tx_count <= tx_count - 1'b1;
                end else if (tx_bit_index == 9) begin
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                    tx_bit_index <= 0;
                    if (char_index == 26)
                        message_active <= 1'b0;
                    else
                        char_index <= char_index + 1'b1;
                end else begin
                    tx_bit_index <= tx_bit_index + 1'b1;
                    tx_shift <= {1'b1, tx_shift[9:1]};
                    tx <= tx_shift[1];
                    tx_count <= DIVISOR - 1;
                end
            end else if (message_active) begin
                tx_shift <= {1'b1, message_byte(char_index, tx_challenge, tx_response), 1'b0};
                tx <= 1'b0;
                tx_count <= DIVISOR - 1;
                tx_bit_index <= 0;
                tx_busy <= 1'b1;
            end
        end
    end
endmodule
