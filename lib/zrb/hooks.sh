#!/bin/bash

zrb_hook_run() {
    local hook_file=$1

    if [ -f "$hook_file" ]; then
        bash "$hook_file"
    fi
}
