library ieee;
use ieee.std_logic_1164.all;
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
    

end architecture rtl;
