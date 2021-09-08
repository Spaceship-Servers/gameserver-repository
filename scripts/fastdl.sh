#!/bin/bash

# by sappho.io

pwd

fastdl_loc="/var/www/sappho.io/files/tf"

# only copy new files
rsync -vu --verbose ./tf/maps/* ${fastdl_loc}/maps
