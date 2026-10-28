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

    constant C_MSG_VOLTAGE : string := "Showing Voltage!";
    constant C_MSG_CURRENT : string := "Showing Current!";

    signal char_index : positive;

    -- To index through Message
    -- if (char_index = C_MSG_VOLTAGE'high) then
    --     char_index <= 1;
    -- else
    --     char_index <= char_index + 1;
    -- end if;
    -- Converts character to ASCII
    function char_to_byte(ch : character) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(character'pos(ch), 8));
    end function;

begin
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
        if rising_edge(i_clk) then
            if (i_rst_n = '0') then
                o_display_mode <= SHOW_VOLTAGE;
                tx_data        <= (others => '0');
                tx_start       <= '0';
                char_index     <= 1; -- Resets char_index to 1

            elsif (rx_valid = '1') then
                

                case rx_data is
                    -- Lowercase decimal starts at 97.
                    -- ASCII 'v'
                    when x"76" => -- (97 + 21) / 16 = 6, R7 | 7 mod 16 = 7
                        o_display_mode <= SHOW_VOLTAGE;
                        tx_data        <= char_to_byte(C_MSG_VOLTAGE(char_index));
                    
                    -- ASCII 'i'
                    when x"69" => -- (97 + 8) / 16 = 6, R9 | 6 mod 16 = 6
                        o_display_mode <= SHOW_CURRENT;
                        tx_data        <= char_to_byte(C_MSG_CURRENT(char_index));
                    
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;

                
