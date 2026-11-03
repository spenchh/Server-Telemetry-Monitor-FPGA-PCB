library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.telemetry_pkg.all;

entity uart_top is
    generic(
        G_CLK_FREQ  : integer range 100 to 100_000_000 := 100_000_000;
        G_BAUD_RATE : positive := 115_200 
    );
    port(
        i_clk          : in std_logic;
        i_rst_n        : in std_logic;
        i_rx           : in std_logic;
        o_tx           : out std_logic;
        o_display_mode : out t_display_mode
    );

end entity;



architecture rtl of uart_top is
    signal tx_data  : std_logic_vector(7 downto 0);
    signal tx_start : std_logic;
    signal tx_busy  : std_logic;
    signal rx_data  : std_logic_vector (7 downto 0);
    signal rx_valid : std_logic;

    signal reply_state : t_reply_state;
    signal reply_kind  : t_reply_kind;

    constant C_MSG_VOLTAGE : string :=
    "Showing Voltage!" & character'val(13) & character'val(10);
    constant C_MSG_CURRENT : string := 
    "Showing Current!" & character'val(13) & character'val(10);
    constant C_MSG_ERROR   : string := 
    "ERROR: Use either 'v' or 'i'!" & character'val(13) & character'val(10);

    signal char_index : positive;

   
    -- Converts character to ASCII
    function char_to_byte(ch : character) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(character'pos(ch), 8));
    end function;

begin
    --------------------------------
    --           UART_TX          --
    --------------------------------
    uart_tx : entity work.uart_tx
    generic map(
        G_CLK_FREQ  => G_CLK_FREQ,
        G_BAUD_RATE => G_BAUD_RATE
    )
    port map(
        i_clk    => i_clk,
        i_rst_n  => i_rst_n,
        i_data   => tx_data, -- Byte to trasmit
        i_start  => tx_start,                    -- One-clock request to send byte
        o_tx     => o_tx,                   -- Serial output to computer
        o_busy   => tx_busy                   -- High while trasnmitting
    );

    --------------------------------
    --           UART_RX          --
    --------------------------------
    uart_rx : entity work.uart_rx
    generic map(
        G_CLK_FREQ  => G_CLK_FREQ,  -- FPGA clock freq in Hz
        G_BAUD_RATE => G_BAUD_RATE       -- UART bits/second
    )
    port map(
        i_clk => i_clk,
        i_rst_n => i_rst_n,
        i_rx => i_rx,
        o_data => rx_data,
        o_valid => rx_valid
    );
    
    process (i_clk) begin
        --------------------------------
        --           RESET            --
        --------------------------------
        if rising_edge(i_clk) then
            if (i_rst_n = '0') then
                o_display_mode <= SHOW_VOLTAGE;
                tx_data        <= (others => '0');
                tx_start       <= '0';
                char_index     <= 1; -- Resets char_index to 1
                reply_state    <= REPLY_IDLE;
                reply_kind     <= REPLY_VOLTAGE;

            else 
                tx_start <= '0';
                case reply_state is
                    when REPLY_IDLE =>

                        if (rx_valid = '1') then

                            case rx_data is
                                -- Lowercase decimal starts at 97.
                                -- ASCII 'v'
                                when x"76" => -- (97 + 21) / 16 = 6, R7 | 7 mod 16 = 7
                                    o_display_mode <= SHOW_VOLTAGE;
                                    reply_kind     <= REPLY_VOLTAGE;
                                    char_index     <= 1;
                                    reply_state    <= REPLY_SEND;
                                
                                -- ASCII 'i'
                                when x"69" => -- (97 + 8) / 16 = 6, R9 | 6 mod 16 = 6
                                    o_display_mode <= SHOW_CURRENT;
                                    reply_kind     <= REPLY_CURRENT;
                                    char_index     <= 1;
                                    reply_state    <= REPLY_SEND;
                                
                                when x"0D" => 
                                    null;
                                when x"0A" =>
                                    null;
                                when others =>
                                    reply_kind  <= REPLY_ERROR;
                                    reply_state <= REPLY_SEND;
                                    char_index  <= 1;

                            end case;
                        end if;

                    when REPLY_SEND =>

                        if (tx_busy = '0') then
                            case reply_kind is
                                when REPLY_VOLTAGE =>
                                    tx_data        <= char_to_byte(C_MSG_VOLTAGE(char_index));
                                    tx_start       <= '1';
                                    reply_state    <= REPLY_WAIT_BUSY;
                                when REPLY_CURRENT =>
                                    tx_data        <= char_to_byte(C_MSG_CURRENT(char_index));
                                    tx_start       <= '1';
                                    reply_state    <= REPLY_WAIT_BUSY;
                                when REPLY_ERROR   =>
                                    tx_data        <= char_to_byte(C_MSG_ERROR(char_index));
                                    tx_start       <= '1';
                                    reply_state    <= REPLY_WAIT_BUSY;
                                when others =>
                                    reply_state    <= REPLY_IDLE;
                            end case;
                        end if;

                    when REPLY_WAIT_BUSY =>  -- Waits until the transmitter accepts the request

                        if (tx_busy = '1') then
                            reply_state <= REPLY_WAIT_DONE;
                        else
                            reply_state <= REPLY_WAIT_BUSY;
                        end if;

                    when REPLY_WAIT_DONE =>
                        if (tx_busy = '0') then
                            case reply_kind is
                                when REPLY_VOLTAGE => 
                                    if (char_index = C_MSG_VOLTAGE'high) then -- check if last char sent = last index 
                                        char_index <= 1;
                                        reply_state <= REPLY_IDLE;
                                    else
                                        char_index <= char_index + 1;
                                        reply_state <= REPLY_SEND;
                                    end if;

                                when REPLY_CURRENT => 
                                    if (char_index = C_MSG_CURRENT'high) then -- check if last char sent = last index 
                                        char_index <= 1;
                                        reply_state <= REPLY_IDLE;
                                    else
                                        char_index <= char_index + 1;
                                        reply_state <= REPLY_SEND;
                                    end if;
                                
                                when REPLY_ERROR =>
                                    if (char_index = C_MSG_ERROR'high) then -- check if last char sent = last index 
                                        char_index <= 1;
                                        reply_state <= REPLY_IDLE;
                                    else
                                        char_index <= char_index + 1;
                                        reply_state <= REPLY_SEND;
                                    end if;

                                end case;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;

                
