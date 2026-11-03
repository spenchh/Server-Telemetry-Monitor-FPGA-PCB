library ieee;
use ieee.std_logic_1164.all;
use work.telemetry_pkg.all;

entity telemetry_top is
    generic(
        G_REFRESH_TICK : positive := 100_000 -- 250 Hz full-display refresh at a 100 MHz clock

    );
    port(
        i_clk     : in std_logic;
        i_rst_n   : in std_logic;
        i_rx      : in std_logic;
        o_anode_n : out std_logic_vector(3 downto 0);
        o_seg_n   : out std_logic_vector(6 downto 0);
        o_dp_n    : out std_logic
    );
end telemetry_top;

architecture rtl of telemetry_top is
    signal rx_data  : std_logic_vector(7 downto 0);
    signal rx_valid : std_logic;
    signal display_mode : t_display_mode;
    signal digit0 : std_logic_vector(3 downto 0);
    signal digit1 : std_logic_vector(3 downto 0);
    signal digit2 : std_logic_vector(3 downto 0);
    signal digit3 : std_logic_vector(3 downto 0);

begin
    decoder : entity work.decode
    generic map(
        G_REFRESH_TICK => G_REFRESH_TICK
    )
    port map(
        i_clk     => i_clk,
        i_digit0  => digit0,
        i_digit1  => digit1,
        i_digit2  => digit2,
        i_digit3  => digit3,
        o_anode_n => o_anode_n,
        o_seg_n   => o_seg_n,
        o_dp_n    => o_dp_n
    );

    uart : entity work.uart_rx
    generic map(
        G_CLK_FREQ  => 100_000_000,  -- FPGA clock freq in Hz
        G_BAUD_RATE => 115_200       -- UART bits/second
    )
    port map(
        i_clk => i_clk,
        i_rst_n => i_rst_n,
        i_rx => i_rx,
        o_data => rx_data,
        o_valid => rx_valid
    );


    process (i_clk)
    begin
        if rising_edge(i_clk) then
            if (i_rst_n = '0') then
                display_mode <= SHOW_VOLTAGE;
            elsif (rx_valid = '1') then
                case rx_data is
                    -- Lowercase decimal starts at 97.
                    -- ASCII 'v'
                    when x"76" => -- (97 + 21) / 16 = 6, R7 | 7 mod 16 = 7
                        display_mode <= SHOW_VOLTAGE;
                    
                    -- ASCII 'i'
                    when x"69" => -- (97 + 8) / 16 = 6, R9 | 6 mod 16 = 6
                        display_mode <= SHOW_CURRENT;
                    
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

    process (display_mode) -- MUX to switch between display modes
    begin
        case display_mode is
            when SHOW_VOLTAGE =>
                digit0 <= "0100";
                digit1 <= "0011";
                digit2 <= "0010";
                digit3 <= "0001";

            when SHOW_CURRENT =>
                digit0 <= "0111";
                digit1 <= "0110";
                digit2 <= "0101";
                digit3 <= "0000";
        end case;
    end process;
end architecture rtl;
