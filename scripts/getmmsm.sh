#!/bin/bash

latestMM=$(curl https://mms.alliedmods.net/mmsdrop/1.12/mmsource-latest-linux -s -S)
latestSM=$(curl https://sm.alliedmods.net/smdrop/1.11/sourcemod-latest-linux -s -S)

mm_url="https://mms.alliedmods.net/mmsdrop/1.12/${latestMM}"
sm_url="https://sm.alliedmods.net/smdrop/1.11/${latestSM}"

if [[ ! ${mm_url} =~ .*"tar.gz"$ ]]; then
    echo "mm url is not fine; ${mm_url}"
    exit 1
fi

if [[ ! ${sm_url} =~ .*"tar.gz"$ ]]; then
    echo "sm url is not fine; ${sm_url}"
    exit 1
fi

echo ${sm_url}

export destfolder="mmsm_xtracted"





echo "rming tempfolder"
rm -rfv /tmp/${destfolder}
echo "mkdiring new destfolder"
mkdir /tmp/${destfolder}
echo "cding to destfolder"
cd /tmp/$destfolder

echo "Curling Metamod Source"
curl "$mm_url" --output "${latestMM}" --limit-rate 4M


echo "Curling SourceMod"
curl "$sm_url" --output "${latestSM}" --limit-rate 4M

echo "Untarring Metamod Source"
tar xfv "${latestMM}" # -C "$destfolder"
echo "Untarring Metamod Source"
tar xfv "${latestSM}" # -C "$destfolder"

echo "rming tgz"
rm ./*.tgz -fv


echo "rming junk"
rm ./cfg                                    -rfv
rm ./addons/sourcemod/plugins               -rfv
rm ./addons/sourcemod/scripting             -rfv
rm ./addons/sourcemod/configs               -rfv
# this gets linux64 folder too lmao
find . -name "*x64*"            -exec rm {} -rfv    \;
find . -name "*blade.so"        -exec rm {} -fv     \;
find . -name "*bms.so"          -exec rm {} -fv     \;
find . -name "*css.so"          -exec rm {} -fv     \;
find . -name "*csgo.so"         -exec rm {} -fv     \;
find . -name "*dods.so"         -exec rm {} -fv     \;
find . -name "*doi.so"          -exec rm {} -fv     \;
find . -name "*ep1.so"          -exec rm {} -fv     \;
find . -name "*ep2.so"          -exec rm {} -fv     \;
find . -name "*hl2dm.so"        -exec rm {} -fv     \;
find . -name "*insurgency.so"   -exec rm {} -fv     \;
find . -name "*l4d*.so"         -exec rm {} -fv     \;
find . -name "*nd.so"           -exec rm {} -fv     \;
find . -name "*sdk2013.so"      -exec rm {} -fv     \;
find . -name "*pvkii.so"          -exec rm {} -fv     \;

echo "DONE"
