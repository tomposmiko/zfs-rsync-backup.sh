#!/bin/bash

ZRB_VERSION="0.6"

zrb_version_print() {
    local command_name=$1

    echo "$command_name $ZRB_VERSION"
}
