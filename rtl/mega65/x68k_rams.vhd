-- MEGA65 port 2026-10-26: Xilinx (and simulator) replacements for the Quartus
-- MegaWizard altsyncram wrappers of the X68000 core. Every entity below has the
-- name, generics and ports of the original file named in its header; the
-- original files stay untouched (they are simply not part of the MEGA65 build).
--
-- Semantics kept from the Quartus settings of the originals:
-- * address (and write data) registered, output unregistered: one clock of read
--   latency, like a plain block RAM;
-- * read during a write on the same port returns the NEW data
--   (NEW_DATA_NO_NBE_READ): write-first;
-- * read during a write on the other port: DONT_CARE in the originals, except
--   slinebuf (OLD_DATA, single clock): read-first there.
-- Init files: Quartus .mif/.hex converted by init/convert.py into one hex word
-- per line, read at elaboration from M65_INIT_DIR.

library ieee;
use ieee.std_logic_1164.all;

package m65_ram_pkg is
	-- Relative to the tool's working directory: Vivado synthesises in
	-- CORE/CORE-R6.runs/synth_1, the simulation runs two levels below a
	-- directory that links X68000_MiSTerMEGA65 (tb/sim).
	constant M65_INIT_DIR : string := "../../X68000_MiSTerMEGA65/rtl/mega65/init/";
end package;

------------------------------------------------------------------------------
-- True dual-port RAM, two clocks, write-first on both ports.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity m65_tdp_ram is
generic(
	AW   : integer := 8;
	DW   : integer := 8;
	INIT : string  := "none"   -- an init file in M65_INIT_DIR, or "none" (MEGA65 port 2026-10-27:
	                           -- not "": Vivado 2022.2 stops with an internal error on an
	                           -- empty string generic once the design also uses XPM)
);
port(
	clk_a  : in  std_logic;
	addr_a : in  std_logic_vector(AW-1 downto 0);
	din_a  : in  std_logic_vector(DW-1 downto 0);
	we_a   : in  std_logic;
	dout_a : out std_logic_vector(DW-1 downto 0);
	clk_b  : in  std_logic;
	addr_b : in  std_logic_vector(AW-1 downto 0);
	din_b  : in  std_logic_vector(DW-1 downto 0);
	we_b   : in  std_logic;
	dout_b : out std_logic_vector(DW-1 downto 0)
);
end m65_tdp_ram;

architecture rtl of m65_tdp_ram is
	type ram_t is array(0 to 2**AW-1) of std_logic_vector(DW-1 downto 0);

	impure function load(name : string) return ram_t is
		file f         : text;
		variable st    : file_open_status;
		variable l     : line;
		variable v     : std_logic_vector(((DW+3)/4)*4-1 downto 0);
		variable r     : ram_t := (others => (others => '0'));
	begin
		if name /= "none" then
			file_open(st, f, name, read_mode);
			if st /= open_ok then   -- ghdl's synthesis does not stop at the assert
				report "m65_tdp_ram: cannot open " & name severity failure;
				return r;
			end if;
			for i in ram_t'range loop
				exit when endfile(f);
				readline(f, l);
				hread(l, v);
				r(i) := v(DW-1 downto 0);
			end loop;
			file_close(f);
		end if;
		return r;
	end function;

	shared variable ram : ram_t := load(INIT);
begin
	process(clk_a)
	begin
		if rising_edge(clk_a) then
			if we_a = '1' then
				ram(to_integer(unsigned(addr_a))) := din_a;
				dout_a <= din_a;
			else
				dout_a <= ram(to_integer(unsigned(addr_a)));
			end if;
		end if;
	end process;

	process(clk_b)
	begin
		if rising_edge(clk_b) then
			if we_b = '1' then
				ram(to_integer(unsigned(addr_b))) := din_b;
				dout_b <= din_b;
			else
				dout_b <= ram(to_integer(unsigned(addr_b)));
			end if;
		end if;
	end process;
end rtl;

------------------------------------------------------------------------------
-- Simple dual-port RAM: write port on wclk, registered read on rclk.
-- With one clock a read of the address being written returns the old data.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity m65_sdp_ram is
generic(
	AW : integer := 8;
	DW : integer := 8
);
port(
	wclk  : in  std_logic;
	waddr : in  std_logic_vector(AW-1 downto 0);
	din   : in  std_logic_vector(DW-1 downto 0);
	we    : in  std_logic;
	rclk  : in  std_logic;
	raddr : in  std_logic_vector(AW-1 downto 0);
	dout  : out std_logic_vector(DW-1 downto 0)
);
end m65_sdp_ram;

architecture rtl of m65_sdp_ram is
	type ram_t is array(0 to 2**AW-1) of std_logic_vector(DW-1 downto 0);
	signal ram : ram_t;
begin
	process(wclk)
	begin
		if rising_edge(wclk) then
			if we = '1' then
				ram(to_integer(unsigned(waddr))) <= din;
			end if;
		end if;
	end process;

	process(rclk)
	begin
		if rising_edge(rclk) then
			dout <= ram(to_integer(unsigned(raddr)));
		end if;
	end process;
end rtl;

------------------------------------------------------------------------------
-- ROM with a registered address.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity m65_rom is
generic(
	AW   : integer := 8;
	DW   : integer := 8;
	INIT : string
);
port(
	clk  : in  std_logic;
	addr : in  std_logic_vector(AW-1 downto 0);
	dout : out std_logic_vector(DW-1 downto 0)
);
end m65_rom;

architecture rtl of m65_rom is
	type rom_t is array(0 to 2**AW-1) of std_logic_vector(DW-1 downto 0);

	impure function load(name : string) return rom_t is
		file f         : text;
		variable st    : file_open_status;
		variable l     : line;
		variable v     : std_logic_vector(((DW+3)/4)*4-1 downto 0);
		variable r     : rom_t := (others => (others => '0'));
	begin
		file_open(st, f, name, read_mode);
		if st /= open_ok then   -- ghdl's synthesis does not stop at the assert
			report "m65_rom: cannot open " & name severity failure;
			return r;
		end if;
		for i in rom_t'range loop
			exit when endfile(f);
			readline(f, l);
			hread(l, v);
			r(i) := v(DW-1 downto 0);
		end loop;
		file_close(f);
		return r;
	end function;

	constant rom : rom_t := load(INIT);
begin
	process(clk)
	begin
		if rising_edge(clk) then
			dout <= rom(to_integer(unsigned(addr)));
		end if;
	end process;
end rtl;

------------------------------------------------------------------------------
-- rtl/cycV/CACHEMEMN.vhd: TDP, two clocks.
library ieee;
use ieee.std_logic_1164.all;

entity CACHEMEMN is
generic(
	awidth :integer :=8;
	dwidth :integer :=8
);
port(
	address_a : in  std_logic_vector(awidth-1 downto 0);
	address_b : in  std_logic_vector(awidth-1 downto 0);
	clock_a   : in  std_logic := '1';
	clock_b   : in  std_logic;
	data_a    : in  std_logic_vector(dwidth-1 downto 0);
	data_b    : in  std_logic_vector(dwidth-1 downto 0);
	wren_a    : in  std_logic := '0';
	wren_b    : in  std_logic := '0';
	q_a       : out std_logic_vector(dwidth-1 downto 0);
	q_b       : out std_logic_vector(dwidth-1 downto 0)
);
end CACHEMEMN;

architecture rtl of CACHEMEMN is
begin
	ram: entity work.m65_tdp_ram generic map(awidth, dwidth)
	port map(clock_a, address_a, data_a, wren_a, q_a, clock_b, address_b, data_b, wren_b, q_b);
end rtl;

------------------------------------------------------------------------------
-- rtl/cycV/CACHEMEMWN.vhd: SDP 16 bit, two clocks. ramtype ("MLAB"/"AUTO")
-- only steered Quartus' block choice; Vivado picks by size.
library ieee;
use ieee.std_logic_1164.all;

entity CACHEMEMWN is
generic(
	awidth  :integer :=8;
	ramtype :string  :="AUTO"
);
port(
	data      : in  std_logic_vector(15 downto 0);
	rdaddress : in  std_logic_vector(awidth-1 downto 0);
	rdclock   : in  std_logic;
	wraddress : in  std_logic_vector(awidth-1 downto 0);
	wrclock   : in  std_logic := '1';
	wren      : in  std_logic := '0';
	q         : out std_logic_vector(15 downto 0)
);
end CACHEMEMWN;

architecture rtl of CACHEMEMWN is
begin
	ram: entity work.m65_sdp_ram generic map(awidth, 16)
	port map(wrclock, wraddress, data, wren, rdclock, rdaddress, q);
end rtl;

------------------------------------------------------------------------------
-- rtl/diskemu/fecbuf.vhd: TDP 256x16, two clocks.
library ieee;
use ieee.std_logic_1164.all;

entity fecbuf is
port(
	address_a : in  std_logic_vector(7 downto 0);
	address_b : in  std_logic_vector(7 downto 0);
	clock_a   : in  std_logic := '1';
	clock_b   : in  std_logic;
	data_a    : in  std_logic_vector(15 downto 0);
	data_b    : in  std_logic_vector(15 downto 0);
	wren_a    : in  std_logic := '0';
	wren_b    : in  std_logic := '0';
	q_a       : out std_logic_vector(15 downto 0);
	q_b       : out std_logic_vector(15 downto 0)
);
end fecbuf;

architecture rtl of fecbuf is
begin
	ram: entity work.m65_tdp_ram generic map(8, 16)
	port map(clock_a, address_a, data_a, wren_a, q_a, clock_b, address_b, data_b, wren_b, q_b);
end rtl;

------------------------------------------------------------------------------
-- rtl/diskemu/sectram.vhd: TDP 512x8, one clock.
library ieee;
use ieee.std_logic_1164.all;

entity sectram is
port(
	address_a : in  std_logic_vector(8 downto 0);
	address_b : in  std_logic_vector(8 downto 0);
	clock     : in  std_logic := '1';
	data_a    : in  std_logic_vector(7 downto 0);
	data_b    : in  std_logic_vector(7 downto 0);
	wren_a    : in  std_logic := '0';
	wren_b    : in  std_logic := '0';
	q_a       : out std_logic_vector(7 downto 0);
	q_b       : out std_logic_vector(7 downto 0)
);
end sectram;

architecture rtl of sectram is
begin
	ram: entity work.m65_tdp_ram generic map(9, 8)
	port map(clock, address_a, data_a, wren_a, q_a, clock, address_b, data_b, wren_b, q_b);
end rtl;

------------------------------------------------------------------------------
-- rtl/diskemu/sramram.vhd: mixed width TDP, one clock: port A 8K x 16 with
-- byte enables, port B 16K x 8. Quartus maps the narrow port little-endian:
-- byte address 2n = data_a(7 downto 0) of word n, 2n+1 = data_a(15 downto 8).
-- Built here as two 8K x 8 banks. Init: rtl/diskemu/sramdefault.hex.
library ieee;
use ieee.std_logic_1164.all;
use work.m65_ram_pkg.all;

entity sramram is
port(
	address_a : in  std_logic_vector(12 downto 0);
	address_b : in  std_logic_vector(13 downto 0);
	byteena_a : in  std_logic_vector(1 downto 0) := (others => '1');
	clock     : in  std_logic := '1';
	data_a    : in  std_logic_vector(15 downto 0);
	data_b    : in  std_logic_vector(7 downto 0);
	wren_a    : in  std_logic := '0';
	wren_b    : in  std_logic := '0';
	q_a       : out std_logic_vector(15 downto 0);
	q_b       : out std_logic_vector(7 downto 0)
);
end sramram;

architecture rtl of sramram is
	signal we_lo_a, we_hi_a, we_lo_b, we_hi_b : std_logic;
	signal qb_lo, qb_hi : std_logic_vector(7 downto 0);
	signal sel_b        : std_logic;
begin
	we_lo_a <= wren_a and byteena_a(0);
	we_hi_a <= wren_a and byteena_a(1);
	we_lo_b <= wren_b and not address_b(0);
	we_hi_b <= wren_b and address_b(0);

	lo: entity work.m65_tdp_ram generic map(13, 8, M65_INIT_DIR & "sram_lo.hex")
	port map(clock, address_a, data_a(7 downto 0), we_lo_a, q_a(7 downto 0),
	         clock, address_b(13 downto 1), data_b, we_lo_b, qb_lo);
	hi: entity work.m65_tdp_ram generic map(13, 8, M65_INIT_DIR & "sram_hi.hex")
	port map(clock, address_a, data_a(15 downto 8), we_hi_a, q_a(15 downto 8),
	         clock, address_b(13 downto 1), data_b, we_hi_b, qb_hi);

	process(clock)
	begin
		if rising_edge(clock) then
			sel_b <= address_b(0);
		end if;
	end process;
	q_b <= qb_hi when sel_b = '1' else qb_lo;
end rtl;

------------------------------------------------------------------------------
-- rtl/diskemu/sxsidrv_rom.vhd: ROM 2K x 18, init rtl/diskemu/sxsidrv.mif.
library ieee;
use ieee.std_logic_1164.all;
use work.m65_ram_pkg.all;

entity sxsidrv_rom is
port(
	address : in  std_logic_vector(10 downto 0);
	clock   : in  std_logic := '1';
	q       : out std_logic_vector(17 downto 0)
);
end sxsidrv_rom;

architecture rtl of sxsidrv_rom is
begin
	rom: entity work.m65_rom generic map(11, 18, M65_INIT_DIR & "sxsidrv.hex")
	port map(clock, address, q);
end rtl;

------------------------------------------------------------------------------
-- rtl/GPALETTE/gpram.vhd: TDP 128x8, two clocks.
library ieee;
use ieee.std_logic_1164.all;

entity gpram is
port(
	address_a : in  std_logic_vector(6 downto 0);
	address_b : in  std_logic_vector(6 downto 0);
	clock_a   : in  std_logic := '1';
	clock_b   : in  std_logic;
	data_a    : in  std_logic_vector(7 downto 0);
	data_b    : in  std_logic_vector(7 downto 0);
	wren_a    : in  std_logic := '0';
	wren_b    : in  std_logic := '0';
	q_a       : out std_logic_vector(7 downto 0);
	q_b       : out std_logic_vector(7 downto 0)
);
end gpram;

architecture rtl of gpram is
begin
	ram: entity work.m65_tdp_ram generic map(7, 8)
	port map(clock_a, address_a, data_a, wren_a, q_a, clock_b, address_b, data_b, wren_b, q_b);
end rtl;

------------------------------------------------------------------------------
-- rtl/LIB/dpssram.vhd: TDP, one clock.
library ieee;
use ieee.std_logic_1164.all;

entity dpssram is
generic(
	awidth :integer :=8;
	dwidth :integer :=8
);
port(
	addr1 :in  std_logic_vector(awidth-1 downto 0);
	wdat1 :in  std_logic_vector(dwidth-1 downto 0);
	wr1   :in  std_logic;
	rdat1 :out std_logic_vector(dwidth-1 downto 0);
	addr2 :in  std_logic_vector(awidth-1 downto 0);
	wdat2 :in  std_logic_vector(dwidth-1 downto 0);
	wr2   :in  std_logic;
	rdat2 :out std_logic_vector(dwidth-1 downto 0);
	clk   :in  std_logic
);
end dpssram;

architecture rtl of dpssram is
begin
	ram: entity work.m65_tdp_ram generic map(awidth, dwidth)
	port map(clk, addr1, wdat1, wr1, rdat1, clk, addr2, wdat2, wr2, rdat2);
end rtl;

------------------------------------------------------------------------------
-- rtl/memory/gvram_bram.vhd: two banks of four 64K x 4 planes; port A
-- read/write with a nibble enable per plane (clock_a), port B read only
-- (clock_b).
library ieee;
use ieee.std_logic_1164.all;

entity gvram_bram is
port(
	c0_address_a   : in  std_logic_vector(15 downto 0);
	c0_data_a      : in  std_logic_vector(15 downto 0);
	c0_wren_a      : in  std_logic := '0';
	c0_nibbleena_a : in  std_logic_vector(3 downto 0) := "1111";
	c0_q_a         : out std_logic_vector(15 downto 0);
	c0_address_b   : in  std_logic_vector(15 downto 0);
	c0_q_b         : out std_logic_vector(15 downto 0);
	c1_address_a   : in  std_logic_vector(15 downto 0);
	c1_data_a      : in  std_logic_vector(15 downto 0);
	c1_wren_a      : in  std_logic := '0';
	c1_nibbleena_a : in  std_logic_vector(3 downto 0) := "1111";
	c1_q_a         : out std_logic_vector(15 downto 0);
	c1_address_b   : in  std_logic_vector(15 downto 0);
	c1_q_b         : out std_logic_vector(15 downto 0);
	clock_a        : in  std_logic;
	clock_b        : in  std_logic
);
end gvram_bram;

architecture rtl of gvram_bram is
	signal zero : std_logic_vector(3 downto 0);
	signal we0, we1 : std_logic_vector(3 downto 0);
begin
	zero <= (others => '0');

	planes: for i in 0 to 3 generate
		we0(i) <= c0_wren_a and c0_nibbleena_a(i);
		we1(i) <= c1_wren_a and c1_nibbleena_a(i);

		bank0: entity work.m65_tdp_ram generic map(16, 4)
		port map(clock_a, c0_address_a, c0_data_a(i*4+3 downto i*4), we0(i), c0_q_a(i*4+3 downto i*4),
		         clock_b, c0_address_b, zero, '0', c0_q_b(i*4+3 downto i*4));
		bank1: entity work.m65_tdp_ram generic map(16, 4)
		port map(clock_a, c1_address_a, c1_data_a(i*4+3 downto i*4), we1(i), c1_q_a(i*4+3 downto i*4),
		         clock_b, c1_address_b, zero, '0', c1_q_b(i*4+3 downto i*4));
	end generate;
end rtl;

------------------------------------------------------------------------------
-- rtl/MFP/KBIF/ktble0_m.vhd: ROM 1K x 7, init ktble0_m.mif.
library ieee;
use ieee.std_logic_1164.all;
use work.m65_ram_pkg.all;

entity ktble0_m is
port(
	address : in  std_logic_vector(9 downto 0);
	clock   : in  std_logic := '1';
	q       : out std_logic_vector(6 downto 0)
);
end ktble0_m;

architecture rtl of ktble0_m is
begin
	rom: entity work.m65_rom generic map(10, 7, M65_INIT_DIR & "ktble0_m.hex")
	port map(clock, address, q);
end rtl;

------------------------------------------------------------------------------
-- rtl/MFP/KBIF/ktbln_m.vhd: ROM 1K x 7, init ktbln_m.mif.
library ieee;
use ieee.std_logic_1164.all;
use work.m65_ram_pkg.all;

entity ktbln_m is
port(
	address : in  std_logic_vector(9 downto 0);
	clock   : in  std_logic := '1';
	q       : out std_logic_vector(6 downto 0)
);
end ktbln_m;

architecture rtl of ktbln_m is
begin
	rom: entity work.m65_rom generic map(10, 7, M65_INIT_DIR & "ktbln_m.hex")
	port map(clock, address, q);
end rtl;

------------------------------------------------------------------------------
-- rtl/SPRITE/bgvram.vhd: SDP 8K x 8, two clocks.
library ieee;
use ieee.std_logic_1164.all;

entity bgvram is
port(
	data      : in  std_logic_vector(7 downto 0);
	rdaddress : in  std_logic_vector(12 downto 0);
	rdclock   : in  std_logic;
	wraddress : in  std_logic_vector(12 downto 0);
	wrclock   : in  std_logic := '1';
	wren      : in  std_logic := '0';
	q         : out std_logic_vector(7 downto 0)
);
end bgvram;

architecture rtl of bgvram is
begin
	ram: entity work.m65_sdp_ram generic map(13, 8)
	port map(wrclock, wraddress, data, wren, rdclock, rdaddress, q);
end rtl;

------------------------------------------------------------------------------
-- rtl/SPRITE/pcgram.vhd: TDP 16K x 8, two clocks.
library ieee;
use ieee.std_logic_1164.all;

entity pcgram is
port(
	address_a : in  std_logic_vector(13 downto 0);
	address_b : in  std_logic_vector(13 downto 0);
	clock_a   : in  std_logic := '1';
	clock_b   : in  std_logic;
	data_a    : in  std_logic_vector(7 downto 0);
	data_b    : in  std_logic_vector(7 downto 0);
	wren_a    : in  std_logic := '0';
	wren_b    : in  std_logic := '0';
	q_a       : out std_logic_vector(7 downto 0);
	q_b       : out std_logic_vector(7 downto 0)
);
end pcgram;

architecture rtl of pcgram is
begin
	ram: entity work.m65_tdp_ram generic map(14, 8)
	port map(clock_a, address_a, data_a, wren_a, q_a, clock_b, address_b, data_b, wren_b, q_b);
end rtl;

------------------------------------------------------------------------------
-- rtl/SPRITE/slinebuf.vhd: SDP 512 x 8, one clock, OLD_DATA on a read of
-- the address being written.
library ieee;
use ieee.std_logic_1164.all;

entity slinebuf is
port(
	clock     : in  std_logic := '1';
	data      : in  std_logic_vector(7 downto 0);
	rdaddress : in  std_logic_vector(8 downto 0);
	wraddress : in  std_logic_vector(8 downto 0);
	wren      : in  std_logic := '0';
	q         : out std_logic_vector(7 downto 0)
);
end slinebuf;

architecture rtl of slinebuf is
begin
	ram: entity work.m65_sdp_ram generic map(9, 8)
	port map(clock, wraddress, data, wren, clock, rdaddress, q);
end rtl;

------------------------------------------------------------------------------
-- rtl/SPRITE/sprreg.vhd: TDP 128 x 8, two clocks.
library ieee;
use ieee.std_logic_1164.all;

entity sprreg is
port(
	address_a : in  std_logic_vector(6 downto 0);
	address_b : in  std_logic_vector(6 downto 0);
	clock_a   : in  std_logic := '1';
	clock_b   : in  std_logic;
	data_a    : in  std_logic_vector(7 downto 0);
	data_b    : in  std_logic_vector(7 downto 0);
	wren_a    : in  std_logic := '0';
	wren_b    : in  std_logic := '0';
	q_a       : out std_logic_vector(7 downto 0);
	q_b       : out std_logic_vector(7 downto 0)
);
end sprreg;

architecture rtl of sprreg is
begin
	ram: entity work.m65_tdp_ram generic map(7, 8)
	port map(clock_a, address_a, data_a, wren_a, q_a, clock_b, address_b, data_b, wren_b, q_b);
end rtl;

------------------------------------------------------------------------------
-- rtl/VIDEO/txtpramh.vhd: TDP 256 x 8, two clocks, init rtl/cycV/TPalH.mif.
library ieee;
use ieee.std_logic_1164.all;
use work.m65_ram_pkg.all;

entity txtpramh is
port(
	address_a : in  std_logic_vector(7 downto 0);
	address_b : in  std_logic_vector(7 downto 0);
	clock_a   : in  std_logic := '1';
	clock_b   : in  std_logic;
	data_a    : in  std_logic_vector(7 downto 0);
	data_b    : in  std_logic_vector(7 downto 0);
	wren_a    : in  std_logic := '0';
	wren_b    : in  std_logic := '0';
	q_a       : out std_logic_vector(7 downto 0);
	q_b       : out std_logic_vector(7 downto 0)
);
end txtpramh;

architecture rtl of txtpramh is
begin
	ram: entity work.m65_tdp_ram generic map(8, 8, M65_INIT_DIR & "tpalh.hex")
	port map(clock_a, address_a, data_a, wren_a, q_a, clock_b, address_b, data_b, wren_b, q_b);
end rtl;

------------------------------------------------------------------------------
-- rtl/VIDEO/txtpraml.vhd: TDP 256 x 8, two clocks, init rtl/cycV/TPalL.mif.
library ieee;
use ieee.std_logic_1164.all;
use work.m65_ram_pkg.all;

entity txtpraml is
port(
	address_a : in  std_logic_vector(7 downto 0);
	address_b : in  std_logic_vector(7 downto 0);
	clock_a   : in  std_logic := '1';
	clock_b   : in  std_logic;
	data_a    : in  std_logic_vector(7 downto 0);
	data_b    : in  std_logic_vector(7 downto 0);
	wren_a    : in  std_logic := '0';
	wren_b    : in  std_logic := '0';
	q_a       : out std_logic_vector(7 downto 0);
	q_b       : out std_logic_vector(7 downto 0)
);
end txtpraml;

architecture rtl of txtpraml is
begin
	ram: entity work.m65_tdp_ram generic map(8, 8, M65_INIT_DIR & "tpall.hex")
	port map(clock_a, address_a, data_a, wren_a, q_a, clock_b, address_b, data_b, wren_b, q_b);
end rtl;
