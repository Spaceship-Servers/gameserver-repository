#!/bin/bash
input="./_default_maps.txt"
while IFS= read -r line
do
    basename "$line" .bsp
done < "$input"
