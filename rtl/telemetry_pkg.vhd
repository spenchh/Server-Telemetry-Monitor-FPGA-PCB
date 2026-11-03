library ieee;
use ieee.std_logic_1164.all;

package telemetry_pkg is
    type t_display_mode is (SHOW_VOLTAGE, SHOW_CURRENT);
    type t_reply_state  is (REPLY_IDLE, REPLY_SEND, REPLY_WAIT_BUSY, REPLY_WAIT_DONE);
    type t_reply_kind   is (REPLY_CURRENT, REPLY_VOLTAGE, REPLY_ERROR);
end package;
