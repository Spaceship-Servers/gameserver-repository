#!/bin/bash
# zero our temp file
> ./maps
# get all the mapcycles and dump the contents to ./maps
find -name *mapcycle.txt -exec cat {} >> ./maps +;
# sort that shit and remove duplicates
sort ./maps -o ./maps -u
# remove comments
sed '/^\/\//d' -i ./maps
# add default map list
cat ./_default_maps.txt >> ./maps
# read our maps file that now has dups, sort it, only print out the duplicates, pipe it to a tmp maps2 file
cat ./maps | sort | uniq -d &> ./maps2
# sync our hard disk
sync
# rm our tmp file
mv ./maps2 ./maps

#!/bin/bash
input="./maps"
while IFS= read -r line
do
  echo $(basename "$line").bsp >> ./maps2
done < "$input"
sync
# rm our tmp file again
mv ./maps2 ./maps
# read our work
cat ./maps
# bye bye
# rm ./maps
