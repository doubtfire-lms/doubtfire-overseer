#!/bin/bash

# Create only the base overseer-instances DIR
# TODO: Change path to XFS volume.
# TODO: Get instance ID as argument and check if it
# already exists. If it does, throw error.
DIR_PATH=/var/tmp/overseer-instances/1

mkdir -p $DIR_PATH
chown -R 1001:999 $DIR_PATH
# chmod -R 777 $DIR_PATH

# User perms
setfacl -R -m u:overseer:rwx $DIR_PATH
setfacl -R -d -m u:overseer:rwx $DIR_PATH

# Group perms
setfacl -R -m g:docker:r $DIR_PATH
setfacl -R -d -m g:docker:r $DIR_PATH

# Mask
setfacl -R -m m:rwx $DIR_PATH
setfacl -R -d -m m:rwx $DIR_PATH

# Other perms
setfacl -R -m o::r $DIR_PATH
setfacl -R -d -m o::r $DIR_PATH
