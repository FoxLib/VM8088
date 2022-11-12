LIB=/usr/share/verilator/include

all: icarus app
#all: icarus
icarus:
	fasm tb.asm tb.bin
	php utils/bin2hex.php tb.bin tb.hex
	iverilog -g2005-sv -DICARUS=1 -o tb.qqq tb.v core.v
	vvp tb.qqq >> /dev/null
	rm tb.qqq
wave:
	gtkwave tb.gtkw
app: ver
	g++ -o tb -I$(LIB) $(LIB)/verilated.cpp tb.cc obj_dir/Vvcard__ALL.a obj_dir/Vcore__ALL.a -lSDL2
	strip tb
	./tb
ver:
	verilator -cc vcard.v
	verilator -cc core.v
	cd obj_dir && make -f Vvcard.mk
	cd obj_dir && make -f Vcore.mk
clean:
	rm tb tb.vcd tb.hex tb.bin
