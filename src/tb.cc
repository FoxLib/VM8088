#include "obj_dir/Vvcard.h"
#include "obj_dir/Vcore.h"
#include "font.h"
#include "tb.h"

int main(int argc, char* argv[]) {

    App* app = new App();

    app->loadarg(argc, argv);

    int fstate = 0; // FIXED cycles
    int tstate = fstate ? fstate : 100000;

    while (app->main()) {

        Uint32 ticks = SDL_GetTicks();
        for (int i = 0; i < tstate; i++) app->tick();
        ticks = SDL_GetTicks() - ticks;

        tstate = fstate ? fstate : (tstate ? (20 * tstate / ticks) : 50000);
    }

    return app->destroy();
}
