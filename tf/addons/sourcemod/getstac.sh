#!/bin/bash
echo "compiling stac [TF2]"
~/tfTEST/tf2/tf/addons/sourcemod/scripting/spcomp -i ./scripting/include ./scripting/stac.sp -o ~/tfTEST/tf2/tf/addons/sourcemod/plugins/stac.smx
sync; sleep 1
cp  ~/tfTEST/tf2/tf/addons/sourcemod/plugins/stac.smx ./plugins/stac.smx
echo ""
#echo "compiling stac [TF2C]"
#/home/steph/tfTEST/tf2/tf/addons/sourcemod/scripting/spcomp TF2C=yep -i ./scripting/include ./scripting/stac.sp -o /home/steph/tfTEST/tf2/tf/addons/sourcemod/plugins/stac_tf2c.smx
#sync; sleep 1
#echo ""
#echo "compiling stac [OF]"
#/home/steph/tfTEST/tf2/tf/addons/sourcemod/scripting/spcomp OF=yep -i ./scripting/include ./scripting/stac.sp -o /home/steph/tfTEST/tf2/tf/addons/sourcemod/plugins/disabled/stac_of.smx
#sync; sleep 1
#echo ""




# echo "compiling stac [TF2 1.10]"
# /home/steph/tfTEST/tf2/tf/addons_1.10/sourcemod/scripting/spcomp -i ./scripting/include ./scripting/stac.sp -o ./plugins/stac.smx
# sync; sleep 1
echo ""
#echo "compiling stac [TF2C 1.10]"
#/home/steph/tfTEST/tf2/tf/addons_1.10/sourcemod/scripting/spcomp TF2C=yep -i ./scripting/include ./scripting/stac.sp -o ./plugins/disabled/stac_tf2c.smx
#sync; sleep 1
#echo ""
#echo "compiling stac [OF 1.10]"
#/home/steph/tfTEST/tf2/tf/addons_1.10/sourcemod/scripting/spcomp OF=yep -i ./scripting/include ./scripting/stac.sp -o ./plugins/disabled/stac_of.smx
#sync; sleep 1
#echo ""
