#!/bin/bash
# colors
source scripts/helpers.sh

# a2s shennanigans
export STEAM_GAMESERVER_RATE_LIMIT_200MS=25
export STEAM_GAMESERVER_PACKET_HANDLER_NO_IPC=1

steamcmd/steamcmd.sh +force_install_dir "${PWD}" +login anonymous +app_update 232250 +exit

./srcds_run "$*"

#startdate=$(date +%Y_%m_%d__%H_%M_%S)
#mkdir ./perf || echo "perf dir already exists"
#find ./perf -mmin +1440 -exec rm -v {} \;
#perf record --output ./perf/"${startdate}"_perf.data \
#    ./srcds_run "$*"; \
#perf inject --jit --input ./perf/"${startdate}"_perf.data --output ./perf/"${startdate}"_perf.jit.data; \
#perf archive ./perf/"${startdate}"_perf.jit.data;
