#!/bin/bash

BASE_DIR=$(dirname $0)
source $BASE_DIR/Configuration.txt

Usage() {
    echo ""
    echo "	Gather outputs of process_iron.sh for all subjects in one directory."

    echo "	Usage: `basename $0` --dir=<SUBJECTS DIRECTORY> --outdir=<OUTPUT DIRECTORY> --subjects=<SUBJECTS> --freesurfer=<FREESURFER DIRECTORY>" 
    echo "	Use commas to separate several subjects"
    echo " "
    exit 1
}


get_opt1() {
    arg=`echo $1 | sed 's/=.*//'`
    echo $arg
}


get_arg1() {
    if [ X`echo $1 | grep '='` = X ] ; then 
	echo "Option $1 requires an argument" 1>&2
	exit 1
    else 
	arg=`echo $1 | sed 's/.*=//'`
	if [ X$arg = X ] ; then
	    echo "Option $1 requires an argument" 1>&2
	    exit 1
	fi
	echo $arg
    fi
}

# initialize variables

SUBJECTS_DIR=`pwd`;
SUBJECTS=""

if [ $# -lt 3 ] ; then Usage; exit 0; fi
while [ $# -ge 1 ] ; do
    iarg=`get_opt1 $1`;
    case "$iarg"
	in
	--dir)
	    SUBJECTS_DIR=`get_arg1 $1`;
	    shift;;
	--outdir)
	    ALL_DIR=`get_arg1 $1`;
	    shift;;
	--subjects)
	    SUBJECTS=`get_arg1 $1|sed 's/,/ /g'`;
	    shift;;
	--freesurfer)
	    FREESURFER_DIR=`get_arg1 $1`;
	    shift;;
	*)
	    #if [ `echo $1 | sed 's/^\(.\).*/\1/'` = "-" ] ; then 
	    echo "Unrecognised option $1" 1>&2
	    exit 1
	    #fi
	    #shift;;
    esac
done

mkdir $ALL_DIR

for SUBJECT in $SUBJECTS; do
    SORTED_DATA_DIR="$SUBJECTS_DIR/$SUBJECT/$ME_SORTED_DATA_SUBDIR"
    cp $SORTED_DATA_DIR/analysis/r2star_norm.nii.gz $ALL_DIR/${SUBJECT}_r2star_norm.nii.gz
    cp $SORTED_DATA_DIR/analysis/QSM_norm.nii.gz $ALL_DIR/${SUBJECT}_QSM_norm.nii.gz

#    ln -s $SORTED_DATA_DIR/analysis/r2star_norm.nii.gz $ALL_DIR/${SUBJECT}_r2star_norm.nii.gz
#    ln -s $SORTED_DATA_DIR/analysis/QSM_norm.nii.gz $ALL_DIR/${SUBJECT}_QSM_norm.nii.gz

done

# put maps together in one
cd $ALL_DIR
fslmerge -t r2star_all.nii.gz $ALL_DIR/*_r2star_norm.nii.gz
gunzip *_r2star_norm.nii.gz
fslmaths r2star_all.nii.gz -Tmean r2star_mean.nii.gz
fslmaths r2star_all.nii.gz -Tstd r2star_std.nii.gz

fslmerge -t QSM_all.nii.gz $ALL_DIR/*_QSM_norm.nii.gz
gunzip *_QSM_norm.nii.gz
fslmaths QSM_all.nii.gz -Tmean QSM_mean.nii.gz
fslmaths QSM_all.nii.gz -Tstd QSM_std.nii.gz

SUBJECTS_DIR=$FREESURFER_DIR

# put together Freesurfer data
asegstats2table --meas mean --stats QSM.stats --subjects $SUBJECTS --tablefile $ALL_DIR/QSM.fs.stats --common-segs -d comma
asegstats2table --meas mean --stats r2star.stats --subjects $SUBJECTS --tablefile $ALL_DIR/r2star.fs.stats --common-segs -d comma
asegstats2table --stats volume.stats --subjects $SUBJECTS --tablefile $ALL_DIR/volumes.fs.stats --common-segs -d comma

