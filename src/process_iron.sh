#!/bin/bash

BASE_DIR=$(dirname $0)
source $BASE_DIR/Configuration.txt

Usage() {
    echo ""
    echo "	Processing pipeline for relaxometry and QSM analysis."
    echo "	Usage: `basename $0` --dir=<SUBJECTS DIRECTORY> --reim=<SUBJECTS W RE/IM> --magphase=<SUBJECTS W MAG/PHASE> --freesurfer=<FREESURFER DIRECTORY>"
    echo " "
    echo "	Store dicom files GRE for sequence in folder 'iron' ( SUBJECTS_DIR/SUBJECT/iron )"
    echo "	Store dicom files for the structural image in folder 'T1' ( SUBJECTS_DIR/SUBJECT/T1 )"
    echo "	Use commas to separate several subjects"
    echo " "
    echo "	The processing pipeline consists of several stages: "
    echo " "
    echo "		SORTING: sort raw data by TE and convert dicom images to nifti"
    echo "		EXTRACTION: brain extraction"
    echo "		SEGMENTATION: create WM masks necessary to create the reference regions"
    echo "		QSM: compute QSM maps"
    echo "		QSM_REFERENCING: reference the QSM maps"
    echo "		RELAXOMETRY: compute relaxometry maps"
    echo "		FREESURFER: extract values from Freesurfer segmentation structures and create cortical surfaces. The images should already be processed with Freesurfer (recon_all) and stored in a the directory FS_ANALYSIS_DIR defined in the configuration file"
    echo " "
    echo "	To deactivate one stage add option --NO_<STAGE NAME>."
    echo "	This can be useful to save processing time or to introduce manual changes at some stage and run the subsequent steps without overwriting the manual changes. F. ex. if the pipeline has been run and changes are made to the QSM maps, you could run:"
    echo "	Usage: `basename $0` --dir=<SUBJECTS_DIRECTORY> --reim=<SUBJECTS W RE/IM> --magphase=<SUBJECTS W MAG/PHASE> --NO_SORTING --NO_EXTRACTION --NO_SEGMENTATION --NO_RELAXOMETRY --NO_QSM  "
    echo "	This will reference the new QSM maps and extract values from Freesurfer segmentation structures without changing the outputs of any of the previous stages."
	
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
SUBJECTS_REIM="";
SUBJECTS_MAGPHASE="";

# stages
DO_SORTING=1
DO_EXTRACTION=1
DO_SEGMENTATION=1
DO_RELAXOMETRY=1
DO_QSM=1
DO_QSM_REFERENCING=1
DO_FREESURFER=1


if [ $# -lt 2 ] ; then Usage; exit 0; fi
while [ $# -ge 1 ] ; do
    iarg=`get_opt1 $1`;
    case "$iarg"
	in
	--dir)
	    SUBJECTS_DIR=`get_arg1 $1`;
	    shift;;
	--reim)
	    SUBJECTS_REIM=`get_arg1 $1|sed 's/,/ /g'`;
	    shift;;
	--magphase)
	    SUBJECTS_MAGPHASE=`get_arg1 $1|sed 's/,/ /g'`;
	    shift;;
	--NO_SORTING)
	    DO_SORTING=0;
	    shift;;
	--NO_EXTRACTION)
	    DO_EXTRACTION=0;
	    shift;;
	--NO_SEGMENTATION)
	    DO_SEGMENTATION=0;
	    shift;;
	--NO_RELAXOMETRY)
	    DO_RELAXOMETRY=0;
	    shift;;
	--NO_QSM)
	    DO_QSM=0;
	    shift;;
	--NO_QSM_REFERENCING)
	    DO_QSM_REFERENCING=0;
	    shift;;
	--NO_FREESURFER)
	    DO_FREESURFER=0;
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

LOGS_DIR=$SUBJECTS_DIR/logs
export FS_ANALYSIS_DIR=$FREESURFER_DIR
mkdir $LOGS_DIR

# SUBJECTS WITH MAG/PHASE
COMPLEX_DATA=0

# do it in parallel
for SUBJECT in $SUBJECTS_MAGPHASE; do
        $EXEC_DIR/processing.sh $SUBJECTS_DIR $SUBJECT $COMPLEX_DATA $ME_DATA_SUBDIR $ME_SORTED_DATA_SUBDIR $FS_ANALYSIS_DIR $DO_SORTING $DO_EXTRACTION $DO_SEGMENTATION $DO_RELAXOMETRY $DO_QSM $DO_QSM_REFERENCING $DO_FREESURFER > $LOGS_DIR/${SUBJECT}_log.txt &
        echo "Processing subject $SUBJECT"
        CURRENT_THREADS=`ps | grep processing.sh | wc -l`
	while [ $MAX_THREADS -le $CURRENT_THREADS ]; do
		sleep 30	            		
                CURRENT_THREADS=`ps | grep processing.sh | wc -l`
		echo "Processing $CURRENT_THREADS subjects"
	done

done


# SUBJECTS WITH MAG/RE/IM

COMPLEX_DATA=1

# do it in parallel

for SUBJECT in $SUBJECTS_REIM; do
        $EXEC_DIR/processing.sh $SUBJECTS_DIR $SUBJECT $COMPLEX_DATA $ME_DATA_SUBDIR $ME_SORTED_DATA_SUBDIR $FS_ANALYSIS_DIR $DO_SORTING $DO_EXTRACTION $DO_SEGMENTATION $DO_RELAXOMETRY $DO_QSM $DO_QSM_REFERENCING $DO_FREESURFER > $LOGS_DIR/${SUBJECT}_log.txt &
        echo "Processing subject $SUBJECT"
        CURRENT_THREADS=`ps | grep processing.sh | wc -l`
	while [ $MAX_THREADS -le $CURRENT_THREADS ]; do
		sleep 30	            		
                CURRENT_THREADS=`ps | grep processing.sh | wc -l`
		echo "Processing $CURRENT_THREADS subjects"
	done
done
