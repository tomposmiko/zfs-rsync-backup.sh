#!/bin/bash

zrb_snapshot_name() {
    local prefix=$1
    local frequency=$2
    local timestamp=$3

    echo "${prefix}_${frequency}_${timestamp}"
}

zrb_snapshot_create() {
    local dataset=$1
    local prefix=$2
    local frequency=$3
    local timestamp=$4
    local snapshot_name

    snapshot_name=$(zrb_snapshot_name "$prefix" "$frequency" "$timestamp")
    zfs snap "$dataset@$snapshot_name"
}
