ROOT=../..
all:
	fasm main.asm main.bin
	php $(ROOT)/utils/makebin.php main.bin $(ROOT)/bios.hex
	cd $(ROOT) && make icarus
