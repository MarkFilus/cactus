library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vhdl_counter is
  port (
    clk   : in  std_logic;
    rst_n : in  std_logic;
    count : out std_logic_vector(23 downto 0)
  );
end entity;

architecture rtl of vhdl_counter is
  signal value : unsigned(23 downto 0) := (others => '0');
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        value <= (others => '0');
      else
        value <= value + 1;
      end if;
    end if;
  end process;
  count <= std_logic_vector(value);
end architecture;
