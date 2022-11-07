#include "tb.h"

int main(int argc, char* argv[]) {

    App* app = new App();
    while (app->main()) {

        // ..
    }

    return app->destroy();
}
