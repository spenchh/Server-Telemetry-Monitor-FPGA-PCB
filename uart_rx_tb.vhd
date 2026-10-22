library ieee;
use ieee.std_logic_1164.all;

entity uart_rx_tb is 
end entity uart_rx_tb;

architecture sim of uart_rx_tb is
    signal tb_clk   : std_logic := '0';
    signal tb_rst_n : std_logic := '0';
    signal tb_rx    : std_logic := '1'; 
    signal tb_data  : std_logic_vector(7 downto 0);
    signal tb_valid : std_logic := '0'; 
begin
    uart : entity work.uart_rx
    generic map(
        G_CLK_FREQ  => 100_000_000,  -- FPGA clock freq in Hz
        G_BAUD_RATE => 115_200       -- UART bits/second
    )
    port map(
        i_clk => tb_clk,
        i_rst_n => tb_rst_n,
        i_rx => tb_rx,
        o_data => tb_data,
        o_valid => tb_valid
    );


end architecture sim;
