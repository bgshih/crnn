#ifndef __CNNCTC_UTILS_HPP__
#define __CNNCTC_UTILS_HPP__

#include <lua.hpp>
#include <luaT.h>
#include <thpp/Tensor.h>
#include <thpp/Storage.h>
#include <fblualib/LuaUtils.h>

#include <vector>
#include <string>
#include <cmath>


template <typename T>
int zeroPadArrayLength(const T* data, int maxLength) {
    int length = maxLength;
    for (int i = 0; i < maxLength; ++i) {
        if (data[i] == 0) {
            length = i;
            break;
        }
    }
    return length;
}


template <class T>
class LogMath {
public:
    static T expMax;
    static T expMin;
    static T expLimit;
    static T logInfinity;
    static T logZero;
    static T logOne;

    static T safeExp(T logX) {
        if (logX == logZero) return 0;
        if (logX >= expLimit) return expMax;
        return std::exp(logX);
    }

    static T logAdd(T logX, T logY) {
        if (logX == logZero) return logY;
        if (logY == logZero) return logX;
        if (logX < logY) std::swap(logX, logY);
        return logX + std::log(1.0 + safeExp(logY - logX));
    }

    static T logMul(T logX, T logY) {
        if (logX == logZero || logY == logZero) return logZero;
        return logX + logY;
    }

    static T logDiv(T logX, T logY) {
        if (logX == logZero) return logZero;
        if (logY == logZero) return logInfinity;
        return logX - logY;
    }
};

template <typename T> T LogMath<T>::expMax      = std::numeric_limits<T>::max();
template <typename T> T LogMath<T>::expMin      = std::numeric_limits<T>::min();
template <typename T> T LogMath<T>::expLimit    = std::log(expMax);
template <typename T> T LogMath<T>::logInfinity = std::numeric_limits<T>::infinity();
template <typename T> T LogMath<T>::logZero     = -LogMath<T>::logInfinity;
template <typename T> T LogMath<T>::logOne      = 0.0;

#endif
