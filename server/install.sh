#!/bin/bash -eu

# This script goes at the root of the 'server' directory, look for adjacent
# 'bom' file which describes files from the 'server' directory to be installed
# to the root.

# Blank lines and # comments in the bomfile are ignored , otherwise each line
# is in form 'owner perms file [!]'

# If the fourth token is not '!' then the target file must not exist.

# If the fourth token is '!' then the target file must exist, and will be overwritten.

# The source file is the copied to the target, and given the specified owner
# and permissions.

# Note new directories must be created before they can be populated. 

# For vi, the preliminary list can created with:
#
#   :r!find .  \( -type f -o -type l \) -printf 'root \%m \%P\n'

# THIS WILL BREAK on filenames that contain spaces... don't do that.

die() { echo $* > &2; exit 1; }

server=${0%/*}
[ -f $server/bom || die "Can't find $server/bom"

sed 's/#.*//;/\S/!d' $server/bom | while read user perm file flag; do
    [ -e $server/$file ] || die "Can't find $server/$file"
    
    if [ "$flag" == "!" ]; then
        [ -e /$file ] || die "/$file does not already exist"
    else
        [ ! -e /$file ] || die "/$file already exists"
    fi    
    
    # careful, don't dereference symlinks!
    if [ -d $server/$file ]; then
        mkdir -p /$file
    else
        cp -P $server/$file /$file          
    fi
    chown -h $user: /$file                  
    [ -L /$file ] || chmod $perm /$file
done    
