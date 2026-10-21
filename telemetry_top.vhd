library ieee;
use ieee.std_logic_1164.all;

entity telemetry_top is
    generic(
        G_REFRESH_TICK : positive := 100_000 -- 250 Hz full-display refresh at a 100 MHz clock

    );
    port(
        i_clk     : in std_logic;
        o_anode_n : out std_logic_vector(3 downto 0);
        o_seg_n   : out std_logic_vector(6 downto 0);
        o_dp_n    : out std_logic
    );
end telemetry_top;

architecture rtl of telemetry_top is
begin
    decoder : entity work.decode
    generic map(
        G_REFRESH_TICK => G_REFRESH_TICK
    )
    port map(
        i_clk     => i_clk,
        i_digit0  => "0100",
        i_digit1  => "0011",
        i_digit2  => "0010",
        i_digit3  => "0001",
        o_anode_n => o_anode_n,
        o_seg_n   => o_seg_n,
        o_dp_n    => o_dp_n
    );

end architecture rtl;
