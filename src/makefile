all: icarus app
	./tb
icarus:
	iverilog -g2005-sv -DICARUS=1 -o tb.qqq tb.v
	vvp tb.qqq >> /dev/null
	rm tb.qqq
app:
	g++ -o tb tb.cc -lSDL2
	strip tb
clean:
	rm tb tb.vcd
