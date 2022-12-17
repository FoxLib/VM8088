#include <SDL2/SDL.h>

#include "app.h"
#include "disasm.cc"

class App {

protected:

    int width, height, frame_length, pticks;
    int frame_id;
    int x, y, _hs, _vs;
    int debug_log;
    int debug_int3;

    SDL_Surface*        screen_surface;
    SDL_Window*         sdl_window;
    SDL_Renderer*       sdl_renderer;
    SDL_PixelFormat*    sdl_pixel_format;
    SDL_Texture*        sdl_screen_texture;
    SDL_Event           evt;
    Uint32*             screen_buffer;

    FILE* sdcard;
    Disassemble* disasm;

    unsigned char kbd[256];
    int kbd_top, kbd_phase, kbd_ticker;

    int tstate = 0;
    int ps_clock = 1,
        ps_data = 1;
    int spi_sclk = 0,
        spi_cnt = 0,
        spi_indata,
        spi_state,
        spi_odata,
        spi_command,
        sd_index,
        sd_cmd_arg;

    Vvga*   vga_mod;
    Vcore*  vcpu_mod;
    Vps2*   ps2_mod;
    Vpctl*  pctl_mod;
    Vsd*    sd_mod;

    unsigned char* memory;
    int  dacmem[256];

public:

    App(int argc, char** argv) {

        FILE* fp;

        x   = 0;
        y   = 0;
        _hs = 1;
        _vs = 0;

        pticks      = 0;
        frame_id    = 0;
        kbd_top     = 0;
        kbd_phase   = 0;
        kbd_ticker  = 0;
        tstate      = 0;

        memory      = (unsigned char*)malloc(64*1024*1024);
        debug_log   = (argc > 1 && strcmp(argv[1], "-d") == 0);
        debug_int3  = (argc > 1 && strcmp(argv[1], "-t") == 0);

        disasm      = new Disassemble(memory);
        vga_mod     = new Vvga();
        vcpu_mod    = new Vcore();
        ps2_mod     = new Vps2();
        pctl_mod    = new Vpctl();
        sd_mod      = new Vsd();

        // Сброс процессора
        vcpu_mod->locked    = 1;
        vcpu_mod->reset_n   = 0;
        pctl_mod->reset_n   = 0;
        vcpu_mod->clock     = 0; vcpu_mod->eval();
        vcpu_mod->clock     = 1; vcpu_mod->eval();
        pctl_mod->clock     = 0; pctl_mod->eval();
        pctl_mod->clock     = 1; pctl_mod->eval();
        vcpu_mod->reset_n   = 1;
        pctl_mod->reset_n   = 1;

        // Настройка VGA
        vga_mod->cursor     = 0;
        vga_mod->cursor_sl  = 14;
        vga_mod->cursor_sh  = 15;

        // Удвоение пикселей
        width        = 640;
        height       = 400;
        frame_length = 50;      // 20 кадров в секунду

        if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO)) {
            exit(1);
        }

        SDL_ClearError();
        screen_buffer       = (Uint32*) malloc(width * height * sizeof(Uint32));
        sdl_window          = SDL_CreateWindow("Verilated VGA Display", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 2*width, 2*height, SDL_WINDOW_SHOWN);
        sdl_renderer        = SDL_CreateRenderer(sdl_window, -1, SDL_RENDERER_PRESENTVSYNC);
        sdl_pixel_format    = SDL_AllocFormat(SDL_PIXELFORMAT_BGRA32);
        sdl_screen_texture  = SDL_CreateTexture(sdl_renderer, SDL_PIXELFORMAT_BGRA32, SDL_TEXTUREACCESS_STREAMING, width, height);
        SDL_SetTextureBlendMode(sdl_screen_texture, SDL_BLENDMODE_NONE);

        // Создать record-файл
        if (fp = fopen("out/record.ppm", "wb")) {
            fclose(fp);
        }

        // Загрузить знакогенератор
        for (int i = 0; i < 4096; i++) memory[0xB9000 + i] = font[i];

        // Заполнение цветами
        for (int i = 0; i < 256; i++) dacmem[i] = dac_init[i];

        // Заполнить чем-нибудь видеобуфер
        for (int i = 0; i < 4096; i += 2) {

            memory[0xB8000 + i]   = (i>>1);
            memory[0xB8000 + i+1] = 0x17;
        }

        // Загрузить bios
        if (fp = fopen("bios.bin", "rb")) {

            fseek(fp, 0, SEEK_END);
            int size = ftell(fp);
            fseek(fp, 0, SEEK_SET);
            fread(memory + 0xF8000, 1, size, fp);
            fclose(fp);

        } else {
            printf("ERROR: bios.bin not found\n");
            exit(1);
        }

        sdcard = fopen("sd.img", "rb+");
    }

    int main() {

        for (;;) {

            Uint32 ticks = SDL_GetTicks();

            while (SDL_PollEvent(& evt)) {

                // Прием событий
                switch (evt.type) {

                    case SDL_QUIT:
                        return 0;

                    case SDL_KEYDOWN:

                        kbd_scancode(evt.key.keysym.scancode, 0);
                        break;

                    case SDL_KEYUP:

                        kbd_scancode(evt.key.keysym.scancode, 1);
                        break;
                }
            }

            // Обновление экрана
            if (ticks - pticks >= frame_length) {

                pticks = ticks;
                update();
                return 1;
            }

            SDL_Delay(1);
        }
    }

    // Один такт 25 мгц
    void tick() {

        // Чтение/Запись в память для процессора
        int address = vcpu_mod->address & 0xfffff;

        // Запись в память (1 Мб доступен)
        if (vcpu_mod->we) memory[ address ] = vcpu_mod->out;

        // Чтение из памяти после записи
        vcpu_mod->in = memory[ address ];

        // Запись в ЦАП
        if (pctl_mod->dac_we) dacmem[ pctl_mod->dac_address ] = pctl_mod->dac_out;

        // Активация дебага только после int1
        if (vcpu_mod->instr == 0 && vcpu_mod->in == 0xF1 && debug_int3) {
            debug_int3 = 0;
            debug_log  = 1;
        }

        if (debug_log) {

            printf("#%08x [%x] %08x | %02x->%04x->%02x %02x | %c%c%c | ",
                tstate++, vcpu_mod->instr, address,
                vcpu_mod->port_i,
                vcpu_mod->port,
                vcpu_mod->port_o,
                vcpu_mod->in,
                vcpu_mod->we ? 'w' : ' ',
                vcpu_mod->port_w ? 'o' : ' ',
                vcpu_mod->port_clk ? 'c' : ' '
            );

            if (vcpu_mod->instr == 0) {
                disasm->disassemble(address);
                printf("%s", disasm->dis_row);
            }

            printf("\n");
        }

        // Обработка событий клавиатуры
        kbd_pop(ps_clock, ps_data);

        ps2_mod->ps_clock       = ps_clock;
        ps2_mod->ps_data        = ps_data;

        // Обмен данными с контроллером порта
        pctl_mod->port_clk      = vcpu_mod->port_clk;
        pctl_mod->port          = vcpu_mod->port;
        pctl_mod->port_o        = vcpu_mod->port_o;
        pctl_mod->port_w        = vcpu_mod->port_w;
        pctl_mod->intl          = vcpu_mod->intl;
        pctl_mod->ps2_data      = ps2_mod->data;
        pctl_mod->ps2_hit       = ps2_mod->done;

        vcpu_mod->port_i        = pctl_mod->port_i;
        vcpu_mod->intr          = pctl_mod->intr;
        vcpu_mod->irq           = pctl_mod->irq;

        vga_mod->videomode      = pctl_mod->videomode;
        vga_mod->cursor         = pctl_mod->cursor;
        vga_mod->cursor_sl      = pctl_mod->cursor_l;
        vga_mod->cursor_sh      = pctl_mod->cursor_h;

        // Чтение из памяти
        vga_mod->data           = memory[ 0xB8000 + vga_mod->address ];
        vga_mod->vga_data       = memory[ 0xA0000 + (vga_mod->vga_address & 65535) ];
        vga_mod->vga_dac_data   = dacmem[ vga_mod->vga_dac_address ];

        // Связь с SD-картой
        sd_mod->sd_signal       = pctl_mod->sd_signal;
        sd_mod->sd_cmd          = pctl_mod->sd_cmd;
        sd_mod->sd_out          = pctl_mod->sd_out;
        pctl_mod->sd_din        = sd_mod->sd_din;
        pctl_mod->sd_busy       = sd_mod->sd_busy;
        pctl_mod->sd_timeout    = sd_mod->sd_timeout;

        sdspi();

        // Активация модулей
        ps2_mod->clock  = 0; ps2_mod->eval();
        sd_mod->clock   = 0; sd_mod->eval();
        vga_mod->clock  = 0; vga_mod->eval();
        pctl_mod->clock = 0; pctl_mod->eval();
        vcpu_mod->clock = 0; vcpu_mod->eval();

        ps2_mod->clock  = 1; ps2_mod->eval();
        sd_mod->clock   = 1; sd_mod->eval();
        vga_mod->clock  = 1; vga_mod->eval();
        pctl_mod->clock = 1; pctl_mod->eval();
        vcpu_mod->clock = 1; vcpu_mod->eval();

        vga(vga_mod->hs, vga_mod->vs, (vga_mod->r*16)*65536 + (vga_mod->g*16)*256 + (vga_mod->b*16));
    }

    // Обновить окно
    void update() {

        SDL_Rect dstRect;

        dstRect.x = 0;
        dstRect.y = 0;
        dstRect.w = 2 * width;
        dstRect.h = 2 * height;

        SDL_UpdateTexture       (sdl_screen_texture, NULL, screen_buffer, width * sizeof(Uint32));
        SDL_SetRenderDrawColor  (sdl_renderer, 0, 0, 0, 0);
        SDL_RenderClear         (sdl_renderer);
        SDL_RenderCopy          (sdl_renderer, sdl_screen_texture, NULL, &dstRect);
        SDL_RenderPresent       (sdl_renderer);
    }

    // Уничтожение окна
    int destroy() {

        free(screen_buffer);
        free(memory);

        if (sdcard) fclose(sdcard);

        SDL_DestroyTexture(sdl_screen_texture);
        SDL_FreeFormat(sdl_pixel_format);
        SDL_DestroyRenderer(sdl_renderer);
        SDL_DestroyWindow(sdl_window);
        SDL_Quit();

        return 0;
    }

    // Установка точки
    void pset(int x, int y, Uint32 cl) {

        if (x < 0 || y < 0 || x >= 640 || y >= 400)
            return;

        screen_buffer[width*y + x] = cl;
    }

    // Сохранение фрейма
    void saveframe() {

        FILE* fp = fopen("out/record.ppm", "ab");
        if (fp) {

            fprintf(fp, "P6\n# Verilator\n640 400\n255\n");
            for (int y = 0; y < 400; y++)
            for (int x = 0; x < 640; x++) {

                int cl = screen_buffer[y*width + x];
                int vl = ((cl >> 16) & 255) + (cl & 0xFF00) + ((cl&255)<<16);
                fwrite(&vl, 1, 3, fp);
            }

            fclose(fp);
        }

        frame_id++;
    }

    // 640 x 400 x 70
    void vga(int hs, int vs, int color) {

        if (hs) x++;

        // Отслеживание изменений HS/VS
        if (_hs == 0 && hs == 1) { x = 0; y++; }
        if (_vs == 1 && vs == 0) { x = 0; y = 0; saveframe(); }

        // Сохранить предыдущее значение
        _hs = hs;
        _vs = vs;

        // Вывод на экран
        pset(x-48, y-35, color);
    }

    // Сканирование нажатой клавиши
    // https://ru.wikipedia.org/wiki/Скан-код
    void kbd_scancode(int scancode, int release) {

        switch (scancode) {

            // Коды клавиш A-Z
            case SDL_SCANCODE_A: if (release) kbd_push(0xF0); kbd_push(0x1C); break;
            case SDL_SCANCODE_B: if (release) kbd_push(0xF0); kbd_push(0x32); break;
            case SDL_SCANCODE_C: if (release) kbd_push(0xF0); kbd_push(0x21); break;
            case SDL_SCANCODE_D: if (release) kbd_push(0xF0); kbd_push(0x23); break;
            case SDL_SCANCODE_E: if (release) kbd_push(0xF0); kbd_push(0x24); break;
            case SDL_SCANCODE_F: if (release) kbd_push(0xF0); kbd_push(0x2B); break;
            case SDL_SCANCODE_G: if (release) kbd_push(0xF0); kbd_push(0x34); break;
            case SDL_SCANCODE_H: if (release) kbd_push(0xF0); kbd_push(0x33); break;
            case SDL_SCANCODE_I: if (release) kbd_push(0xF0); kbd_push(0x43); break;
            case SDL_SCANCODE_J: if (release) kbd_push(0xF0); kbd_push(0x3B); break;
            case SDL_SCANCODE_K: if (release) kbd_push(0xF0); kbd_push(0x42); break;
            case SDL_SCANCODE_L: if (release) kbd_push(0xF0); kbd_push(0x4B); break;
            case SDL_SCANCODE_M: if (release) kbd_push(0xF0); kbd_push(0x3A); break;
            case SDL_SCANCODE_N: if (release) kbd_push(0xF0); kbd_push(0x31); break;
            case SDL_SCANCODE_O: if (release) kbd_push(0xF0); kbd_push(0x44); break;
            case SDL_SCANCODE_P: if (release) kbd_push(0xF0); kbd_push(0x4D); break;
            case SDL_SCANCODE_Q: if (release) kbd_push(0xF0); kbd_push(0x15); break;
            case SDL_SCANCODE_R: if (release) kbd_push(0xF0); kbd_push(0x2D); break;
            case SDL_SCANCODE_S: if (release) kbd_push(0xF0); kbd_push(0x1B); break;
            case SDL_SCANCODE_T: if (release) kbd_push(0xF0); kbd_push(0x2C); break;
            case SDL_SCANCODE_U: if (release) kbd_push(0xF0); kbd_push(0x3C); break;
            case SDL_SCANCODE_V: if (release) kbd_push(0xF0); kbd_push(0x2A); break;
            case SDL_SCANCODE_W: if (release) kbd_push(0xF0); kbd_push(0x1D); break;
            case SDL_SCANCODE_X: if (release) kbd_push(0xF0); kbd_push(0x22); break;
            case SDL_SCANCODE_Y: if (release) kbd_push(0xF0); kbd_push(0x35); break;
            case SDL_SCANCODE_Z: if (release) kbd_push(0xF0); kbd_push(0x1A); break;

            // Цифры
            case SDL_SCANCODE_0: if (release) kbd_push(0xF0); kbd_push(0x45); break;
            case SDL_SCANCODE_1: if (release) kbd_push(0xF0); kbd_push(0x16); break;
            case SDL_SCANCODE_2: if (release) kbd_push(0xF0); kbd_push(0x1E); break;
            case SDL_SCANCODE_3: if (release) kbd_push(0xF0); kbd_push(0x26); break;
            case SDL_SCANCODE_4: if (release) kbd_push(0xF0); kbd_push(0x25); break;
            case SDL_SCANCODE_5: if (release) kbd_push(0xF0); kbd_push(0x2E); break;
            case SDL_SCANCODE_6: if (release) kbd_push(0xF0); kbd_push(0x36); break;
            case SDL_SCANCODE_7: if (release) kbd_push(0xF0); kbd_push(0x3D); break;
            case SDL_SCANCODE_8: if (release) kbd_push(0xF0); kbd_push(0x3E); break;
            case SDL_SCANCODE_9: if (release) kbd_push(0xF0); kbd_push(0x46); break;

            // Keypad
            case SDL_SCANCODE_KP_0: if (release) kbd_push(0xF0); kbd_push(0x70); break;
            case SDL_SCANCODE_KP_1: if (release) kbd_push(0xF0); kbd_push(0x69); break;
            case SDL_SCANCODE_KP_2: if (release) kbd_push(0xF0); kbd_push(0x72); break;
            case SDL_SCANCODE_KP_3: if (release) kbd_push(0xF0); kbd_push(0x7A); break;
            case SDL_SCANCODE_KP_4: if (release) kbd_push(0xF0); kbd_push(0x6B); break;
            case SDL_SCANCODE_KP_5: if (release) kbd_push(0xF0); kbd_push(0x73); break;
            case SDL_SCANCODE_KP_6: if (release) kbd_push(0xF0); kbd_push(0x74); break;
            case SDL_SCANCODE_KP_7: if (release) kbd_push(0xF0); kbd_push(0x6C); break;
            case SDL_SCANCODE_KP_8: if (release) kbd_push(0xF0); kbd_push(0x75); break;
            case SDL_SCANCODE_KP_9: if (release) kbd_push(0xF0); kbd_push(0x7D); break;

            // Специальные символы
            case SDL_SCANCODE_GRAVE:        if (release) kbd_push(0xF0); kbd_push(0x0E); break;
            case SDL_SCANCODE_MINUS:        if (release) kbd_push(0xF0); kbd_push(0x4E); break;
            case SDL_SCANCODE_EQUALS:       if (release) kbd_push(0xF0); kbd_push(0x55); break;
            case SDL_SCANCODE_BACKSLASH:    if (release) kbd_push(0xF0); kbd_push(0x5D); break;
            case SDL_SCANCODE_LEFTBRACKET:  if (release) kbd_push(0xF0); kbd_push(0x54); break;
            case SDL_SCANCODE_RIGHTBRACKET: if (release) kbd_push(0xF0); kbd_push(0x5B); break;
            case SDL_SCANCODE_SEMICOLON:    if (release) kbd_push(0xF0); kbd_push(0x4C); break;
            case SDL_SCANCODE_APOSTROPHE:   if (release) kbd_push(0xF0); kbd_push(0x52); break;
            case SDL_SCANCODE_COMMA:        if (release) kbd_push(0xF0); kbd_push(0x41); break;
            case SDL_SCANCODE_PERIOD:       if (release) kbd_push(0xF0); kbd_push(0x49); break;
            case SDL_SCANCODE_SLASH:        if (release) kbd_push(0xF0); kbd_push(0x4A); break;
            case SDL_SCANCODE_BACKSPACE:    if (release) kbd_push(0xF0); kbd_push(0x66); break;
            case SDL_SCANCODE_SPACE:        if (release) kbd_push(0xF0); kbd_push(0x29); break;
            case SDL_SCANCODE_TAB:          if (release) kbd_push(0xF0); kbd_push(0x0D); break;
            case SDL_SCANCODE_CAPSLOCK:     if (release) kbd_push(0xF0); kbd_push(0x58); break;
            case SDL_SCANCODE_LSHIFT:       if (release) kbd_push(0xF0); kbd_push(0x12); break;
            case SDL_SCANCODE_LCTRL:        if (release) kbd_push(0xF0); kbd_push(0x14); break;
            case SDL_SCANCODE_LALT:         if (release) kbd_push(0xF0); kbd_push(0x11); break;
            case SDL_SCANCODE_RSHIFT:       if (release) kbd_push(0xF0); kbd_push(0x59); break;
            case SDL_SCANCODE_RETURN:       if (release) kbd_push(0xF0); kbd_push(0x5A); break;
            case SDL_SCANCODE_ESCAPE:       if (release) kbd_push(0xF0); kbd_push(0x76); break;
            case SDL_SCANCODE_NUMLOCKCLEAR: if (release) kbd_push(0xF0); kbd_push(0x77); break;
            case SDL_SCANCODE_KP_MULTIPLY:  if (release) kbd_push(0xF0); kbd_push(0x7C); break;
            case SDL_SCANCODE_KP_MINUS:     if (release) kbd_push(0xF0); kbd_push(0x7B); break;
            case SDL_SCANCODE_KP_PLUS:      if (release) kbd_push(0xF0); kbd_push(0x79); break;
            case SDL_SCANCODE_KP_PERIOD:    if (release) kbd_push(0xF0); kbd_push(0x71); break;
            case SDL_SCANCODE_SCROLLLOCK:   if (release) kbd_push(0xF0); kbd_push(0x7E); break;

            // F1-F12 Клавиши
            case SDL_SCANCODE_F1:   if (release) kbd_push(0xF0); kbd_push(0x05); break;
            case SDL_SCANCODE_F2:   if (release) kbd_push(0xF0); kbd_push(0x06); break;
            case SDL_SCANCODE_F3:   if (release) kbd_push(0xF0); kbd_push(0x04); break;
            case SDL_SCANCODE_F4:   if (release) kbd_push(0xF0); kbd_push(0x0C); break;
            case SDL_SCANCODE_F5:   if (release) kbd_push(0xF0); kbd_push(0x03); break;
            case SDL_SCANCODE_F6:   if (release) kbd_push(0xF0); kbd_push(0x0B); break;
            case SDL_SCANCODE_F7:   if (release) kbd_push(0xF0); kbd_push(0x83); break;
            case SDL_SCANCODE_F8:   if (release) kbd_push(0xF0); kbd_push(0x0A); break;
            case SDL_SCANCODE_F9:   if (release) kbd_push(0xF0); kbd_push(0x01); break;
            case SDL_SCANCODE_F10:  if (release) kbd_push(0xF0); kbd_push(0x09); break;
            case SDL_SCANCODE_F11:  if (release) kbd_push(0xF0); kbd_push(0x78); break;
            case SDL_SCANCODE_F12:  if (release) kbd_push(0xF0); kbd_push(0x07); break;

            // Расширенные клавиши
            case SDL_SCANCODE_LGUI:         kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x1F); break;
            case SDL_SCANCODE_RGUI:         kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x27); break;
            case SDL_SCANCODE_APPLICATION:  kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x2F); break;
            case SDL_SCANCODE_RCTRL:        kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x14); break;
            case SDL_SCANCODE_RALT:         kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x11); break;
            case SDL_SCANCODE_KP_DIVIDE:    kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x4A); break;
            case SDL_SCANCODE_KP_ENTER:     kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x5A); break;

            case SDL_SCANCODE_INSERT:       kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x70); break;
            case SDL_SCANCODE_HOME:         kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x6C); break;
            case SDL_SCANCODE_END:          kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x69); break;
            case SDL_SCANCODE_PAGEUP:       kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x7D); break;
            case SDL_SCANCODE_PAGEDOWN:     kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x7A); break;
            case SDL_SCANCODE_DELETE:       kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x71); break;

            case SDL_SCANCODE_UP:           kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x75); break;
            case SDL_SCANCODE_DOWN:         kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x72); break;
            case SDL_SCANCODE_LEFT:         kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x6B); break;
            case SDL_SCANCODE_RIGHT:        kbd_push(0xE0); if (release) kbd_push(0xF0); kbd_push(0x74); break;

            // Клавиша PrnScr
            case SDL_SCANCODE_PRINTSCREEN: {

                if (release == 0) {

                    kbd_push(0xE0); kbd_push(0x12);
                    kbd_push(0xE0); kbd_push(0x7C);

                } else {

                    kbd_push(0xE0); kbd_push(0xF0); kbd_push(0x7C);
                    kbd_push(0xE0); kbd_push(0xF0); kbd_push(0x12);
                }

                break;
            }

            // Клавиша Pause
            case SDL_SCANCODE_PAUSE: {

                kbd_push(0xE1);
                kbd_push(0x14); if (release) kbd_push(0xF0); kbd_push(0x77);
                kbd_push(0x14); if (release) kbd_push(0xF0); kbd_push(0x77);
                break;
            }
        }
    }

    // Нажатие на клавишу
    void kbd_push(int data) {

        if (kbd_top >= 255) return;
        kbd[kbd_top] = data;
        kbd_top++;
    }

    // Извлечение PS/2
    void kbd_pop(int& ps_clock, int& ps_data) {

        // В очереди нет клавиш для нажатия
        if (kbd_top == 0) return;

        // 25000000/2000 = 12.5 kHz Очередной полутакт для PS/2
        if (++kbd_ticker >= 2000) {

            ps_clock = kbd_phase & 1;

            switch (kbd_phase) {

                // Старт-бит [=0]
                case 0: case 1: ps_data = 0; break;

                // Бит четности
                case 18: case 19:

                    ps_data = 1;
                    for (int i = 0; i < 8; i++)
                        ps_data ^= !!(kbd[0] & (1 << i));

                    break;

                // Стоп-бит [=1]
                case 20: case 21: ps_data = 1; break;

                // Небольшая задержка между нажатиями клавиш
                case 22: case 23:
                case 24: case 25:

                    ps_clock = 1;
                    ps_data  = 1;
                    break;

                // Завершение
                case 26:

                    // Удалить символ из буфера
                    for (int i = 0; i < kbd_top - 1; i++)
                        kbd[i] = kbd[i+1];

                    kbd_top--;
                    kbd_phase = -1;
                    ps_clock  = 1;
                    break;

                // Отсчет битов от 0 до 7
                // 0=2,3   | 1=4,5   | 2=6,7   | 3=8,9
                // 4=10,11 | 5=12,13 | 6=14,15 | 7=16,17
                default:

                    ps_data = !!(kbd[0] & (1 << ((kbd_phase >> 1) - 1)));
                    break;
            }

            kbd_ticker = 0;
            kbd_phase++;
        }
    }

    // Эмуляция протокола SDCard
    void sdspi() {

        unsigned char bchar;

        // Отослать данные контроллеру
        if (sd_mod->SPI_SCLK == 1) {
            sd_mod->SPI_MISO = (spi_odata & (1 << (7 - spi_cnt))) ? 1 : 0;
        }

        // Прием данных от SPI
        if (spi_sclk == 0 && sd_mod->SPI_SCLK == 1) {

            // Прием данных от контроллера
            spi_indata = ((spi_indata << 1) | sd_mod->SPI_MOSI) & 0xff;

            // Отладка
            if (debug_log) {
                printf("[%d] > spi_cnt | in=%d, out=%d\n", spi_cnt, sd_mod->SPI_MOSI, sd_mod->SPI_MISO);
            }

            spi_cnt++;
            if (spi_cnt == 8) {

                spi_cnt = 0;

                if (debug_log) {
                    printf("%02x | O=%02X | I=%02X\n", spi_state, spi_indata, spi_odata);
                }

                switch (spi_state) {

                    // IDLE
                    case 0: {

                        spi_odata = 0xFF;

                        // Получена команда
                        if (spi_indata >= 0x40 && spi_indata < 0x80) {

                            // printf("CMD ACCEPT\n");
                            spi_command = spi_indata & 0x3F;
                            spi_state = 1;
                        }

                        break;
                    }

                    // COMMAND ARG4+CHKSUM
                    case 1: spi_state = 2; sd_cmd_arg  =  spi_indata << 24;  break;
                    case 2: spi_state = 3; sd_cmd_arg |= (spi_indata << 16); break;
                    case 3: spi_state = 4; sd_cmd_arg |= (spi_indata << 8);  break;
                    case 4: spi_state = 5; sd_cmd_arg |= spi_indata; break;
                    case 5: {

                        // OK: ответ на комманду
                        spi_odata = 0x00;

                        if (debug_log) printf("ARG=%08x\n", sd_cmd_arg);

                        switch (spi_command) {

                            // INIT
                            case 0x00:

                                spi_state = 6;
                                spi_odata = 0x01;
                                break;

                            case 0x08: spi_state = 7; break;

                            // ACMD
                            case 0x37: spi_state = 6; break;
                            case 0x29: spi_state = 6; break;
                            case 0x3A: spi_state = 11; break;

                            // READ
                            case 0x11: spi_state = 15; break;

                            default: printf("UNK: %02x\n", spi_command); exit(1);
                        }

                        break;
                    }

                    // Инициализация без до-параметров
                    case 6: spi_state = 0; spi_odata = 0xFF; break;

                    // 48h CMD-8
                    case 7: case 8: case 9: spi_state = spi_state + 1; spi_odata = 0xff; break;
                    case 10: spi_state = 0; spi_odata = 0xAA; break;

                    // 3A
                    case 11: spi_state = 12; spi_odata = 0xc0; break;
                    case 12: case 13: spi_state = spi_state + 1; spi_odata = 0xff; break;
                    case 14: spi_state = 0; break;

                    // READ
                    case 15: spi_state = 16; spi_odata = 0xFE; sd_index = 0; break;
                    // Читать сектор
                    case 16: {

                        if (sdcard) {

                            fseek(sdcard, 512*sd_cmd_arg + sd_index, SEEK_SET);
                            sd_index++;
                            fread(&bchar, 1, 1, sdcard);
                            spi_odata = bchar;

                        } else {
                            spi_odata = 0xff;
                        }

                        // Последний байт и выход
                        if (sd_index == 512) {
                            spi_state = 0;
                        }

                        break;
                    }
                }
            }
        }

        spi_sclk = sd_mod->SPI_SCLK;
    }
};
