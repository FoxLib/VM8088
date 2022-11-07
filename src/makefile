#all: icarus app
all: icarus
icarus:
	iverilog -g2005-sv -DICARUS=1 -o tb.qqq tb.v core.v
	vvp tb.qqq >> /dev/null
	rm tb.qqq
wave:
	gtkwave tb.gtkw
app:
	g++ -o tb tb.cc -lSDL2
	strip tb
	./tb
clean:
	rm tb tb.vcd
