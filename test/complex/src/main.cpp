#include "platform.h"
#include "io.h"
#include <string>

int main(int argc, char *argv[]) {
    std::string platform = getPlatformName();
    log(platform);
    return 0;
}
