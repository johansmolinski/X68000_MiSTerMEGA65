LIBRARY	IEEE;
USE	IEEE.STD_LOGIC_1164.ALL;
USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity cacheext is
generic(
	awidth	:integer	:=8;
	cdcfilt	:integer	:=1
);
port(
	wraddr	:in std_logic_vector(awidth-1 downto 0);
	wr		:in std_logic;
	clr		:in std_logic;
	busy	:out std_logic;

	rdaddr	:in std_logic_vector(awidth-1 downto 0);
	rd		:out std_logic;
	masken	:in std_logic;

	wclk	:in std_logic;
	ram_ce  :in std_logic := '1';
	rclk	:in std_logic;
	sys_ce  :in std_logic := '1';
	-- MEGA65 port 2026-11-05 (temporary): R3 bring-up (MegaX doc/history.md): 1 mask (wclk), 0 rdb
	-- (rclk). Original: the port list ended with rstn.
	rstn	:in std_logic;
	dbg_o	:out std_logic_vector(1 downto 0)
);
end cacheext;

architecture rtl of cacheext is
constant len	:integer 	:=2**awidth;
signal	wrote	:std_logic_vector(len-1 downto 0);
signal	rdaddr_l	:std_logic_vector(awidth-1 downto 0);
signal	rdb1	:std_logic;
signal	mask	:std_logic;
signal	mcount	:integer range 0 to 3;
-- MEGA65 port 2026-11-05: the mask waits for rclk edges seen through a toggle in rclk's domain,
-- not by sampling rclk itself in wclk's (see below). Original:
-- signal	srclk	:std_logic;
-- signal	lrclk	:std_logic;
signal	rtog	:std_logic;			-- toggles at every rclk edge with sys_ce (rclk)
signal	rtog_s	:std_logic;			-- ... in wclk
signal	rtog_d	:std_logic;
signal	rdb	:std_logic;
begin

	process(wclk,rstn)
	variable iwaddr	:integer range 0 to len-1;
	begin
		if rising_edge(wclk) then
			if(rstn='0')then
				wrote<=(others=>'0');
			elsif(ram_ce = '1')then
				if(clr='1')then
					wrote<=(others=>'0');
				elsif(wr='1')then
					iwaddr:=conv_integer(wraddr);
					wrote(iwaddr)<='1';
				end if;
			end if;
		end if;
	end process;

	-- MEGA65 port 2026-11-05: after clr the mask holds rd low until rclk's side has stepped its
	-- read pipeline (rdaddr_l, rdb1, rdb) past the wrote bits from before the clear. The original
	-- counted rclk's rising edges by sampling rclk as data in wclk's domain (srclk, lrclk). On the
	-- MEGA65 rclk (40 MHz) and wclk (80 MHz) come from one MMCM with aligned edges, so every sample
	-- falls on an edge of rclk and what it sees depends on the routing: in megax-hr7..9 (R3
	-- bring-up, the HyperRAM builds) one read block per build never saw an edge, its mask stayed
	-- low, and the 68000 waited for that block's word for ever (doc/history.md 2026-11-05). Now
	-- rclk's side toggles rtog at every edge it steps its pipeline (sys_ce), wclk's side takes it
	-- through two registers and counts its changes (one or two wclk clocks later than the
	-- original, rd only waits that much longer). Original:
	-- process(wclk,rstn)begin
	-- 	if rising_edge(wclk) then
	-- 		if(rstn='0')then
	-- 			mask<='1';
	-- 			mcount<=0;
	-- 			srclk<='1';
	-- 			lrclk<='1';
	-- 		elsif(ram_ce = '1')then
	-- 			srclk<=rclk;
	-- 			lrclk<=srclk;
	-- 			if(clr='1')then
	-- 				mask<='0';
	-- 				mcount<=2;
	-- 			elsif(lrclk='0' and srclk='1')then
	-- 				if(mcount>0)then
	-- 					mcount<=mcount-1;
	-- 				else
	-- 					mask<='1';
	-- 				end if;
	-- 			end if;
	-- 		end if;
	-- 	end if;
	-- end process;
	process(rclk)begin
		if rising_edge(rclk) then
			if(rstn='0')then
				rtog<='0';
			elsif(sys_ce = '1')then
				rtog<=not rtog;
			end if;
		end if;
	end process;

	process(wclk,rstn)begin
		if rising_edge(wclk) then
			if(rstn='0')then
				mask<='1';
				mcount<=0;
				rtog_s<='0';
				rtog_d<='0';
			elsif(ram_ce = '1')then
				rtog_s<=rtog;
				rtog_d<=rtog_s;
				if(clr='1')then
					mask<='0';
					mcount<=2;
				elsif(rtog_s/=rtog_d)then
					if(mcount>0)then
						mcount<=mcount-1;
					else
						mask<='1';
					end if;
				end if;
			end if;
		end if;
	end process;

	gen_cdc: if cdcfilt/=0 generate
		process(rclk,rstn)
		variable iraddr	:integer range 0 to len-1;
		begin
			if rising_edge(rclk) then
				if(rstn='0')then
					rdaddr_l<=(others=>'0');
					rdb1<='0';
					rdb<='0';
				elsif(sys_ce = '1')then
					iraddr:=conv_integer(rdaddr);
					rdaddr_l<=rdaddr;
					rdb1<=wrote(iraddr);
					if(rdaddr_l=rdaddr)then
						rdb<=rdb1 and wrote(iraddr);
					else
						rdb<='0';
					end if;
				end if;
			end if;
		end process;
	end generate;

	gen_seq: if cdcfilt=0 generate
		process(rclk,rstn)
		variable iraddr	:integer range 0 to len-1;
		begin
			if rising_edge(rclk) then
				if(rstn='0')then
					rdb<='0';
				elsif(sys_ce = '1')then
					iraddr:=conv_integer(rdaddr);
					rdb<=wrote(iraddr);
				end if;
			end if;
		end process;
	end generate;

	busy<='0';
	dbg_o<=mask & rdb;	-- MEGA65 port 2026-11-05 (temporary): R3 bring-up

	rd<=	(rdb and (not clr) and mask) when masken='1' else (rdb and (not clr));
end rtl;
