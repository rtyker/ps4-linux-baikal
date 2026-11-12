#!/bin/sh

MESA=/home/noob404/mesa \

LD_LIBRARY_PATH=$MESA/lib64:$MESA/lib:$LD_LIBRARY_PATH \
LIBGL_DRIVERS_PATH=$MESA/lib64/dri:$MESA/lib/dri \
VK_ICD_FILENAMES=$MESA/share/vulkan/icd.d/radeon_icd.x86_64.json:$MESA/share/vulkan/icd.d/radeon_icd.x86.json \
D3D_MODULE_PATH=$MESA/lib64/d3d/d3dadapter9.so.1:$MESA/lib/d3d/d3dadapter9.so.1 \
	exec "$@"