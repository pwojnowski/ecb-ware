#!/bin/tcsh

# Script for creating ECB releases.
# Author: Jesper Nordenberg
#
# $Id: make_release.sh,v 1.12 2002/07/25 12:35:08 berndl Exp $

set files="*.el HISTORY Makefile make.bat README RELEASE_NOTES ecb.texi ecb.html ecb.info"
set version="1.80"

set name=ecb-$version
set release_dir=releases
set dir=$release_dir/$name


rm -rf $dir
mkdir -p $dir
cp $files $dir
cd $release_dir

echo "Creating .zip file..."
rm -f $name.zip
zip -rv $name.zip $name

echo "\nCreating .tar.gz file..."
rm -f $name.tar.gz
tar cvzf $name.tar.gz $name
