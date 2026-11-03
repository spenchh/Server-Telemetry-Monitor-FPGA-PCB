library ieee;
use ieee.std_logic_1164.all;

-- UART is idle high
-- Start bit = '0', Stop bit = '1'

entity uart_tx is
    generic(
        G_CLK_FREQ : integer range 100 to 100_000_000 := 100_000_000;
        G_BAUD_RATE : positive := 115_200
    );
    port(
        i_clk    : in std_logic;
        i_rst_n  : in std_logic;
        i_data   : in std_logic_vector(7 downto 0); -- Byte to trasmit
        i_start  : in std_logic;                    -- One-clock request to send byte
        o_tx     : out std_logic;                   -- Serial output to computer
        o_busy   : out std_logic                    -- High while trasnmitting
    );
end uart_tx;

architecture rtl of uart_tx is
    constant C_CLKS_PER_BIT : positive := (G_CLK_FREQ / G_BAUD_RATE);
    signal clk_count        : natural  range 0 to C_CLKS_PER_BIT-1;
  
    type t_tx_state is (TX_IDLE, TX_START, TX_DATA, TX_STOP);
    signal state            : t_tx_state;
    
    signal bit_index        : natural range 0 to 7 := 0; -- tracks data bit being sent
    signal tx_byte          : std_logic_vector(7 downto 0); -- holds byte during transmission

begin
    process (i_clk)
    begin
        if rising_edge(i_clk) then 
            if (i_rst_n = '0') then
                o_tx      <= '1';   -- UART idles high
                o_busy    <= '0';   -- Nothing being trasmitted
                clk_count <= 0;
                state     <= TX_IDLE; 
                bit_index <= 0;
                tx_byte   <= (others => '0');
            else
                case state is
                    when TX_IDLE  => -- wait for internal 'i_start' request

                        clk_count <= 0;
                        o_busy    <= '0';
                        o_tx      <= '1';
                        bit_index <= 0;
                        
                        if (i_start = '1') then
                            tx_byte <= i_data;
                            state   <= TX_START;
                            o_busy  <= '1';
                            o_tx    <= '0';
                        end if;

                    when TX_START => -- Hold start bit for one full bit period

                        if (clk_count = (C_CLKS_PER_BIT-1)) then
                            clk_count <= 0;
                            state <= TX_DATA;
                            o_tx  <= tx_byte(bit_index); -- read after holding start bit for one cycle
                            bit_index <= bit_index + 1;
                        else
                            clk_count <= clk_count + 1; 
                        end if;

                    when TX_DATA  => -- Send eight stored data bits, one at a time

                        if (clk_count = (C_CLKS_PER_BIT-1)) then
                            clk_count <= 0;

                            -- Change state AFTER fully reading byte and hold stop bit high
                            if (bit_index = 0) then 
                                o_tx <= '1';
                                state <= TX_STOP;
                            elsif (bit_index = 7) then
                                o_tx <= tx_byte(bit_index);
                                bit_index <= 0;
                            else
                                o_tx <= tx_byte(bit_index);
                                bit_index <= bit_index + 1;
                            end if;
                        else
                            clk_count <= clk_count + 1; 
                        end if;

                    when TX_STOP  => -- Hold stop bit for one full bit period

                        if (clk_count = (C_CLKS_PER_BIT-1)) then
                            clk_count <= 0;
                            o_busy <= '0';
                            state <= TX_IDLE;
                        else
                            clk_count <= clk_count + 1; 
                        end if;

                end case;
            end if;
        end if;
    end process;
end architecture rtl;
