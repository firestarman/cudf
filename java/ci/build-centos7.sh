#!/bin/bash

set -e

WORKDIR=`pwd`

export GIT_COMMITTER_NAME="ci"
export GIT_COMMITTER_EMAIL="ci@nvidia.com"

export GIT_DESCRIBE_TAG=`git describe --tags`
export MINOR_VERSION=`echo $GIT_DESCRIBE_TAG | grep -o -E '([0-9]+\.[0-9]+)'`
echo "MINOR_VERSION: $MINOR_VERSION, DEPLOY_JAR: $DEPLOY_JAR"

cd /rapids/
git clone --recurse-submodules https://github.com/rapidsai/rmm.git -b branch-$MINOR_VERSION
git clone --recurse-submodules https://github.com/rapidsai/dlpack.git -b cudf

gcc --version

export CUDACXX=/usr/local/cuda/bin/nvcc
export INSTALL_PREFIX=/usr/local/rapids

rm -rf /rapids/rmm/build
mkdir -p /rapids/rmm/build
cd /rapids/rmm/build
cmake .. -DCMAKE_CXX11_ABI=OFF -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX
make -j${PARALLEL_LEVEL} install

rm -rf /rapids/dlpack/build
mkdir -p /rapids/dlpack/build
cd /rapids/dlpack/build
cmake .. -DCMAKE_CXX11_ABI=OFF -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX
make -j${PARALLEL_LEVEL} install

rm -rf $WORKDIR/cpp/build
mkdir -p $WORKDIR/cpp/build
cd $WORKDIR/cpp/build
export RMM_ROOT=$INSTALL_PREFIX
export NVSTRINGS_ROOT=$INSTALL_PREFIX
export DLPACK_ROOT=$INSTALL_PREFIX
cmake .. -DCMAKE_CXX11_ABI=OFF
make -j${PARALLEL_LEVEL} install DESTDIR=$INSTALL_PREFIX

cp /usr/lib/libboost_filesystem.so $INSTALL_PREFIX/lib/

cd $WORKDIR/java

MVN_TARGETS="install"
MVN_PROFILES="default,abiOff"

if [[ "$DEPLOY_JAR" == "1" ]]; then
    MVN_TARGETS="install deploy"
fi

mvn clean -Dmaven.repo.local=$WORKSPACE/.m2 -P "$MVN_PROFILES" $MVN_TARGETS -DskipTests

mkdir -p "../dist"
cp target/*.jar "../dist/"
