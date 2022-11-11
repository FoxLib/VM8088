#include "obj_dir/Vvcard.h"
#include "obj_dir/Vcore.h"
#include "tb.h"

int main(int argc, char* argv[]) {

    App* app = new App();

    while (app->main()) {

        for (int i = 0; i < 75000; i++) {
            app->tick();
        }
    }

    return app->destroy();
}
