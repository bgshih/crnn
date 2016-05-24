#include <iostream>
#include <vector>
#include <string>
#include <cmath>

#include <lua.hpp>
#include <luaT.h>
#include <thpp/Tensor.h>
#include <thpp/Storage.h>
#include <fblualib/LuaUtils.h>

#include "utils.hpp"


namespace {

const int blankLabel = 0;


template <class T>
int forwardBackward(lua_State* L) {
    const thpp::Tensor<T> input     = fblualib::luaGetTensorChecked<T>(L, 1);
    const thpp::Tensor<int> targets = fblualib::luaGetTensorChecked<int>(L, 2);
    const bool forwardOnly          = lua_toboolean(L, 3);
    thpp::Tensor<T> gradInput       = fblualib::luaGetTensorChecked<T>(L, 4);

    const int nFrame      = input.size(0);
    const int inputLength = input.size(1);
    const int nClasses    = input.size(2);
    const int maxTargetlength = targets.size(1);
    if (!forwardOnly) {
        gradInput.resizeAs(input);
        gradInput.fill(LogMath<T>::logZero);
    }

    thpp::Tensor<T> losses({nFrame});
    losses.fill(0);

    #pragma omp parallel for
    for (int i = 0; i < nFrame; ++i) {
        const thpp::Tensor<T>& input_i = input[i];
        const int* targetData_i = targets[i].data();
        const int targetLength = zeroPadArrayLength(targetData_i, maxTargetlength);
        const int nSegment = 2 * targetLength + 1;

        // compute forward variables
        thpp::Tensor<T> fvars({inputLength, nSegment});
        fvars.fill(LogMath<T>::logZero);
        fvars.at({0, 0}) = input_i.at({0, 0});
        if (nSegment > 1) {
            fvars.at({0, 1}) = input_i.at({0, targetData_i[0]});
        }
        for (int t = 1; t < inputLength; ++t) {
            const thpp::Tensor<T>& currLogActs = input_i[t];
            const thpp::Tensor<T>& prefFvars = fvars[t-1];
            int sBegin = std::max(0, nSegment - (2 * (inputLength - t)));
            int sEnd = std::min(nSegment, 2 * (t + 1));
            for (int s = sBegin; s < sEnd; ++s) { // FIXME: < or <= ??
                T fv;
                if (s % 2 == 1) { // non-blank
                    int labelIndex = s/2;
                    int label = targetData_i[labelIndex];
                    fv = LogMath<T>::logAdd(prefFvars.at(s), prefFvars.at(s-1));
                    if (s > 1 && label != targetData_i[labelIndex-1]) {
                        fv = LogMath<T>::logAdd(fv, prefFvars.at(s-2));
                    }
                    fv = LogMath<T>::logMul(fv, currLogActs.at(label));
                } else { // blank
                    fv = prefFvars.at(s);
                    if (s > 0) {
                        fv = LogMath<T>::logAdd(fv, prefFvars.at(s-1));
                    }
                    fv = LogMath<T>::logMul(fv, currLogActs.at(0)); // 0 for blank
                }
                fvars.at({t,s}) = fv;
            }
        }

        // compute log-likelihood
        T logProb = fvars.at({inputLength-1, nSegment-1});
        if (nSegment > 1) {
            logProb = LogMath<T>::logAdd(logProb, fvars.at({inputLength-1, nSegment-2}));
        }
        losses.at(i) = (-logProb);

        if (!forwardOnly) {
            // compute backward variables
            thpp::Tensor<T> bvars({inputLength, nSegment});
            bvars.fill(LogMath<T>::logZero);
            bvars.at({inputLength-1, nSegment-1}) = LogMath<T>::logOne;
            if (nSegment > 1) {
                bvars.at({inputLength-1, nSegment-2}) = LogMath<T>::logOne;
            }
            for (int t = inputLength-2; t >= 0; --t) {
                const thpp::Tensor<T>& prevLogActs = input_i[t+1];
                const thpp::Tensor<T>& prevBvars = bvars[t+1];
                int sBegin = std::max(0, nSegment - (2 * (inputLength - t)));
                int sEnd = std::min(nSegment, 2 * (t + 1));
                for (int s = sBegin; s < sEnd; ++s) {
                    T bv;
                    if (s % 2 == 1) {
                        const int labelIndex = s/2;
                        int label = targetData_i[labelIndex];
                        bv = LogMath<T>::logAdd(
                            LogMath<T>::logMul(prevBvars.at(s), prevLogActs.at(label)),
                            LogMath<T>::logMul(prevBvars.at(s+1), prevLogActs.at(blankLabel)));
                        if (s < nSegment-2) {
                            const int prevLabel = targetData_i[labelIndex+1];
                            if (label != prevLabel) {
                                bv = LogMath<T>::logAdd(bv,
                                    LogMath<T>::logMul(prevBvars.at(s+2), prevLogActs.at(prevLabel)));
                            }
                        }
                    } else {
                        int labelIndex = s/2;
                        int label = targetData_i[labelIndex];
                        bv = LogMath<T>::logMul(prevBvars.at(s), prevLogActs.at(blankLabel));
                        if (s < nSegment-1) {
                            bv = LogMath<T>::logAdd(bv,
                                LogMath<T>::logMul(prevBvars.at(s+1), prevLogActs.at(label)));
                        }
                    }
                    bvars.at({t,s}) = bv;
                }
            }

            // compute gradients on inputs
            for (int t = 0; t < inputLength; ++t) {
                const thpp::Tensor<T>& currLogFv = fvars[t];
                const thpp::Tensor<T>& currLogBv = bvars[t];
                std::vector<T> logDeDy(nClasses, LogMath<T>::logZero);
                for (int s = 0; s < nSegment; ++s) {
                    int k = (s%2==1) ? targetData_i[s/2] : blankLabel;
                    logDeDy[k] = LogMath<T>::logAdd(logDeDy[k],
                        LogMath<T>::logMul(currLogFv.at(s), currLogBv.at(s)));
                }
                for (int k = 0; k < nClasses; ++k) {
                    gradInput.at({i,t,k}) = -LogMath<T>::safeExp(
                        LogMath<T>::logDiv(logDeDy[k], logProb));
                }
            }
        } // if (!forwardOnly)
    }

    // return loss
    fblualib::luaPushTensor(L, losses);
    return 1;
}


template <class T>
int naiveDecoding(lua_State* L) {
    const thpp::Tensor<T>& input = fblualib::luaGetTensorChecked<T>(L, 1);
    const int nFrame = input.size(0);
    const int inputLength = input.size(1);

    thpp::Tensor<long> rawPred_ = input.max(2).second; // [nFrame x inputLength]
    thpp::Tensor<int> rawPred({nFrame, inputLength});
    rawPred.copy(rawPred_);

    thpp::Tensor<int> pred({nFrame, inputLength});
    pred.fill(0);

    for (int i = 0; i < nFrame; ++i) {
        std::vector<int> predVec;
        const int* rawPredData_i = rawPred[i].data();
        int* predData_i = pred[i].data();
        for (int t = 0; t < inputLength; ++t) {
            if (rawPredData_i[t] != 0 && !(t > 0 && rawPredData_i[t] == rawPredData_i[t-1])) {
                predVec.push_back(rawPredData_i[t]);
            }
        }
        for (int j = 0; j < (int)predVec.size(); ++j) {
            predData_i[j] = predVec[j];
        }
    }

    fblualib::luaPushTensor(L, pred);
    fblualib::luaPushTensor(L, rawPred);
    return 2;
}


// register functions
template <class T>
class Registerer {
private:
    static const luaL_Reg functions_[];
public:
    static void registerFunctions(lua_State* L);
};

template <class T>
const luaL_Reg Registerer<T>::functions_[] = {
    {"CTC_forwardBackward", forwardBackward<T>},
    {"CTC_naiveDecoding", naiveDecoding<T>},
    {nullptr, nullptr},
};

template <class T>
void Registerer<T>::registerFunctions(lua_State* L) {
    luaT_pushmetatable(L, thpp::Tensor<T>::kLuaTypeName);
    luaT_registeratname(L, functions_, "nn");
    lua_pop(L, 1);
}

} // namespace

void initCtc(lua_State* L) {
    Registerer<float>::registerFunctions(L);
    Registerer<double>::registerFunctions(L);
}
