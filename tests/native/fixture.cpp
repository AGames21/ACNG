// Original ACNG toolchain fixture, unrelated to either game's implementation.
#include <cstdio>
extern "C" double acng_fixture_scale(double speed, double factor) {
    return speed * factor;
}
int main() {
    volatile double input = 10.0;
    double result = acng_fixture_scale(input, 0.7);
    std::printf("ACNG toolchain fixture: %.1f\n", result);
    return result == 7.0 ? 0 : 1;
}
