VRL=/usr/share/verilator/include
DIR=core32
RUN=tbc
# icarus | tbc

all: $(RUN)

icarus: core.v
	iverilog -g2005-sv -DICARUS=1 -I$(DIR) -o tb.qqq tb.v core.v
	vvp tb.qqq >> /dev/null
	rm tb.qqq

wave:
	gtkwave tb.gtkw

# Запуск с логированием в tb.log
log:
	./tb -d > tb.log

# Логирование, но остановка на int3
int3:
	./tb -t > tb.log

run:
	./tb

tbc: core.v icarus verilate
	g++ -o tb -I$(VRL) $(VRL)/verilated.cpp tb.cc \
		obj_dir/Vvga__ALL.a \
		obj_dir/Vcore__ALL.a \
		obj_dir/Vps2__ALL.a \
		obj_dir/Vpctl__ALL.a \
		obj_dir/Vsd__ALL.a \
	-lSDL2
	./tb
verilate:
	verilator -cc vga.v
	verilator -cc core.v
	verilator -cc ps2.v
	verilator -cc pctl.v
	verilator -cc sd.v
	cd obj_dir && make -f Vvga.mk
	cd obj_dir && make -f Vcore.mk
	cd obj_dir && make -f Vps2.mk
	cd obj_dir && make -f Vpctl.mk
	cd obj_dir && make -f Vsd.mk
core.v: $(DIR)/core_top.v $(DIR)/core_decl.v $(DIR)/core_exec.v $(DIR)/core_proc.v $(DIR)/core_alu.v
	cd $(DIR) && make
video:
	ffmpeg -framerate 70 -r 60 -i out/record.ppm -vf "scale=w=1280:h=800,pad=width=1920:height=1080:x=320:y=140:color=black" -sws_flags neighbor -sws_dither none -f mp4 -q:v 0 -vcodec mpeg4 -y record.mp4
clean:
	rm -rf *.o tb tb.log obj_dir bios.bin bios.hex tb.vcd