#!/bin/bash -e
#
#  Copyright (c) 2014, Facebook, Inc.
#  All rights reserved.
#
#  This source code is licensed under the BSD-style license found in the
#  LICENSE file in the root directory of this source tree. An additional grant
#  of patent rights can be found in the PATENTS file in the same directory.
#
# Modified for 14.04 installation.
set -o pipefail

if [[ ! -r ./Tensor.h ]]; then
  echo "Please run from the thpp subdirectory." >&2
  exit 1
fi

rm -rf gtest-1.7.0 gtest-1.7.0.zip
curl -JLO https://github.com/google/googletest/archive/release-1.7.0.zip
# if [[ $($SHA -b googletest-release-1.7.0.zip | cut -d' ' -f1) != \
#       'f89bc9f55477df2fde082481e2d709bfafdb057b' ]]; then
#   echo "Invalid googletest-release-1.7.0.zip file" >&2
#   exit 1
# fi
unzip googletest-release-1.7.0.zip
mv googletest-release-1.7.0 gtest-1.7.0
# Build in a separate directory
mkdir -p build
cd build

# Configure
cmake ..

# Make
make

# Run tests
ctest

# Install
sudo make install
