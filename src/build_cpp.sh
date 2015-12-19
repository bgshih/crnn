#!/bin/bash
cd cpp/
mkdir build
cd build/
cmake ..
make
cp *.so ../../
