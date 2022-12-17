CC=clang
# gcc -mgeneral-regs-only
COPT=-Os -I../../include -ffreestanding -fno-pie -nostdlib -m32 -mno-sse -mno-mmx -Wl,-dead_strip
DEPS=nasm.o main.o
LDTR=-m elf_i386 -nostdlib -nodefaultlibs -Ttext=0xF8000 -Tdata=0x800
ROOT=../..

all: $(DEPS)
	ld $(LDTR) $(DEPS) --oformat binary -o bios.bin
	ld $(LDTR) $(DEPS) -o bios.elf
	objdump -Mintel -S bios.elf > bios.lst
	rm bios.elf *.o
	php $(ROOT)/utils/makebin.php bios.bin $(ROOT)/bios.hex
	php $(ROOT)/utils/bin2mif.php bios.bin 32768 > $(ROOT)/de0/bios.mif
	mv bios.bin $(ROOT)/bios.bin
	cd $(ROOT) && make
nasm.o: main.asm
	nasm -felf32 -o nasm.o main.asm
%.o: %.c
	$(CC) $(COPT) -c $< -o $@
clean:
	rm -f *.o *.ini

