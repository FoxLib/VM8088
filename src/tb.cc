#include "obj_dir/Vvga.h"
#include "obj_dir/Vcore.h"
#include "obj_dir/Vps2.h"
#include "obj_dir/Vpctl.h"
#include "obj_dir/Vsd.h"
#include "app.cc"

int main(int argc, char** argv) {

    int   instr  = 125000;
    float target = 100;

    Verilated::commandArgs(argc, argv);
    App* app = new App(argc, argv);

    while (app->main()) {

        Uint32 start = SDL_GetTicks();

        // Автоматическая коррекция кол-ва инструкции в секунду
        for (int i = 0; i < instr; i++) app->tick();

        // Коррекция тактов
        Uint32 delay = (SDL_GetTicks() - start);
        instr = (instr * (0.5 * target) / (float)delay);
        instr = instr < 1000 ? 1000 : instr;

        if (Verilated::gotFinish()) break;
    }

    return app->destroy();
}
