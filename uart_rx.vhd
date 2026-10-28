library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.definitions_pkg.all;

-- FPGA Clock runs 100,000,000 in a second which is 10 ns per cycle
-- UART sends 115,200 bits/second which is 1 bit every 868 FPGA clock cycles
-- 868 FPGA clock cycles happen during one bit, which lasts 8.68 microseconds
entity uart_rx is 
    generic(
        G_CLK_FREQ  : positive := 100_000_000;  -- FPGA clock freq in Hz
        G_BAUD_RATE : positive := 115_200       -- UART bits/second
    );
    port(
        i_clk   : in  std_logic;
        i_rst_n : in  std_logic;
        i_rx    : in  std_logic; -- UART is serial so incoming byte comes 1 bit at a time
        o_data  : out std_logic_vector(7 downto 0);
        o_valid : out std_logic
    );
end uart_rx;

architecture rtl of uart_rx is
    -- reduces the chance of metastability propagating
    signal   rx_meta        : std_logic; -- first ff
    signal   rx_sync        : std_logic; -- second ff
    constant C_CLKS_PER_BIT : positive := (G_CLK_FREQ / G_BAUD_RATE); -- cycles/bit = freq/baud
    signal   clk_count      : natural  range 0 to C_CLKS_PER_BIT-1; -- natural datatype is 2-state and allows you to represent actual number

    type t_rx_state is (RX_IDLE, RX_START, RX_DATA, RX_STOP);
    signal state            : t_rx_state;

    signal bit_index        : natural range 0 to 7; -- Tracks which bit we're receiving
    signal rx_byte          : std_logic_vector(7 downto 0); -- Holds last byte as bits arrive
begin
    process(i_clk) begin
        if rising_edge (i_clk) then 
            if (i_rst_n = '0') then
                o_valid    <= '0';
                o_data     <= (others => '0');
                clk_count  <=  0;
                rx_meta    <= '1';
                rx_sync    <= '1';   
                bit_index  <= 0;
                rx_byte    <= (others => '0');
                state      <= RX_IDLE;    
            else
                rx_meta <= i_rx;      -- double ff
                rx_sync <= rx_meta;   -- double ff
                o_valid <= '0';

                case state is
                    when RX_IDLE  => -- Looks for possible start bit
                        clk_count <= 0;
                        if (rx_sync = '0') then -- Transmission is starting
                            state <= RX_START;
                        end if;

                    when RX_START => -- Time and confirm start bit
                        clk_count <= clk_count + 1;

                        if (clk_count = (C_CLKS_PER_BIT/2 - 1)) then -- Check start bit near its midpoint to reject short low glitches
                            clk_count <= 0;
                            if (rx_sync = '0') then
                                bit_index <= 0;
                                state     <= RX_DATA;
                            else
                                state     <= RX_IDLE;
                            end if;
                        end if;

                    when RX_DATA  => -- Time and collect data bits
                        
                        if (clk_count = (C_CLKS_PER_BIT - 1)) then
                            clk_count <= 0;
                            rx_byte(bit_index) <= rx_sync;

                            if (bit_index = 7) then
                                state <= RX_STOP;
                            else
                                bit_index <= bit_index + 1;
                            end if;
                        else
                            clk_count <= clk_count + 1;
                        end if;

                    when RX_STOP  => -- Check stop bit
                        
                        if (clk_count = (C_CLKS_PER_BIT - 1)) then
                            clk_count <= 0;
                            state     <= RX_IDLE;
                            if (rx_sync = '1') then -- stop bit has expected level
                                o_data    <= rx_byte;
                                o_valid   <= '1';
                            end if;
                        else
                            clk_count <= clk_count + 1;
                        end if;

                end case;
                

            end if;
    end if;
    end process;
end architecture rtl;
