/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2018
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

class Foo {};

int fun() {
    throw Foo();
    return 0;
}
