#!/bin/tcsh

# Script for creating ECB releases.
# Author: Jesper Nordenberg
#
# $Id: make_release.sh,v 1.3 2001/05/31 21:16:44 creator Exp $

set files="*.el HISTORY Makefile make.bat README RELEASE_NOTES"
set version="1.31"

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
