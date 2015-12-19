#include <lua.hpp>

void initCtc(lua_State* L);

extern "C" int luaopen_libcrnn(lua_State* L) {
    initCtc(L);
    return 0;
}
