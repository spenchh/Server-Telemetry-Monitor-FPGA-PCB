library ieee;
use ieee.std_logic_1164.all;


entity uart_rx is 
    port(
        i_clk   : in  std_logic;
        i_rst_n : in  std_logic;
        i_rx    : in  std_logic;
        o_data  : out std_logic_vector(7 downto 0);
        o_valid : out std_logic
    );
end uart_rx;

architecture rtl of decode is
begin
    process(i_clk) begin 

    end process;
end architecture rtl;
