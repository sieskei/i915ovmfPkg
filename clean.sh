#!/bin/bash
source ./config

#remove test dir
rm -rf "$TEST_DIR"

#remove build dir
cd $WORKSPACE
rm -rf Build