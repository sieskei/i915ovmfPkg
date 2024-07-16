#!/bin/bash

source ./config

set -e

mkdir -p "$WORKSPACE"

if [ ! -L "$WORKSPACE/i915ovmfPkg" ]; then
    echo "configuring workspace"
    pushd "$WORKSPACE"
        ln -s "$EDK2_PATH" edk2
        ln -s "$EDK2_PLATFORMS_PATH" edk2-platforms
        ln -s "$REPO_DIR" i915ovmfPkg
        mkdir -p Conf
        #ln -s "$REPO_DIR/target.txt" Conf/target.txt
        #cp "$REPO_DIR/target.txt" Conf/
    popd
else
  echo "Workspace already configured."
fi

export PACKAGES_PATH=$WORKSPACE/edk2:$WORKSPACE/edk2-platforms

cd $WORKSPACE
. edk2/edksetup.sh --reconfig
if [ ! -d "$WORKSPACE/edk2/BaseTools/Source/C/bin" ]; then
    echo "Compiling base tools."
    make -C edk2/BaseTools
    echo "compiled edk2 base tools!"
else
    echo "edk2 BaseTools already built, skipping."
fi

#Overwrite the generated target in $WORKSPACE/Conf
if [ -f "$WORKSPACE/Conf/target.txt" ]; then
    rm "$WORKSPACE/Conf/target.txt"
    cp "$REPO_DIR/target.txt" Conf/
    echo "wrote our own target to Conf."
fi

#now attempt to build the project
build -v -b $BUILD_TYPE -p i915ovmfPkg/i915ovmf.dsc || exit
echo "==== success ===="
