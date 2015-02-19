#!/bin/bash
# Benjamin Garzon, January 2015
# syntax: processing.sh SUBJECTS_DIR SUBJECT COMPLEXDATA ME_DATA_SUBDIR ME_SORTED_DATA_SUBDIR FS_ANALYSIS_DIR DO_SORTING DO_EXTRACTION DO_SEGMENTATION DO_RELAXOMETRY DO_QSM DO_QSM_REFERENCING DO_FREESURFER
# environment variables: EXEC_DIR STRUCTURES MNI MNI_BRAIN

SUBJECTS_DIR=$1
SUBJECT=$2
COMPLEX_DATA=$3
ME_DATA_SUBDIR=$4
ME_SORTED_DATA_SUBDIR=$5
FS_ANALYSIS_DIR=$6
DO_SORTING=$7
DO_EXTRACTION=$8
DO_SEGMENTATION=$9
DO_RELAXOMETRY=${10}
DO_QSM=${11} 
DO_QSM_REFERENCING=${12}
DO_FREESURFER=${13} 

# definitions
STRUCTURAL_DIR="$SUBJECTS_DIR/$SUBJECT/T1"
DATA_DIR="$SUBJECTS_DIR/$SUBJECT/$ME_DATA_SUBDIR"
SORTED_DATA_DIR="$SUBJECTS_DIR/$SUBJECT/$ME_SORTED_DATA_SUBDIR"
RESULTS_DIR="$SORTED_DATA_DIR/analysis"

# relaxometry constant
RELAXOMETRY_CONSTANT=0
# remove dummy scans from fMRI data
FIRST_VOLUME=2
TOTAL_VOLUMES=178
# leave empty to include boundaries
STRUCTURES_SUFFIX=_no_bound
# number of echoes
ECHOS=8
#how many echoes above threshold should we have at least
# set to 0 to NOT exclude voxels
THR_ECHOS=4
# threshold to remove voxels
THR=1000
PD_THR=4000
# calculate exclusion mask (set to 0 to use one manually modified)
CALC_EXCLUSION=1
# desired size for the reference region
GROW_VOXELS=1000
# % to remove when segmenting from parcellation
ROBUST=15

##########

function execute {
    echo -n "Doing: $1 ... "
    $1
    echo "done!"
}

echo "Processing SUBJECT $SUBJECT"

########### DATA SORTING
if [ $DO_SORTING = 1 ]; then
echo "Sorting data"

if [ $COMPLEX_DATA = 1 ]; then
    DATA_DIRS="MAG RE IM"
else
    DATA_DIRS="MAG PHASE"
fi

# sort the DICOM files according to TE
execute "$EXEC_DIR/sort_dicom_GRE.py $DATA_DIR $SORTED_DATA_DIR $COMPLEX_DATA $SORTED_DATA_DIR/TEs.txt $SORTED_DATA_DIR/imaging_freq.txt"

# convert DICOM to NIFTI and merge in 4D files
cd $SORTED_DATA_DIR

for d in $DATA_DIRS;
do
   cd $d
   for i in TE*; do echo $i; cd $i; dcm2nii *.dcm; cd ..; done
   for i in TE*; do echo $i; cp $i/2*.nii.gz $i.nii.gz; done
   fslmerge -t data.nii.gz TE*.nii.gz
   rm -r TE*
   cd ..
done

mkdir $RESULTS_DIR

cd $STRUCTURAL_DIR 
dcm2nii *.dcm
mv 2*1.nii.gz $RESULTS_DIR/T1.nii.gz
rm *.nii.gz

# organize complex data
if [ $COMPLEX_DATA = 1 ]; then
# create complex data file
execute "fslcomplex -complex $SORTED_DATA_DIR/RE/data $SORTED_DATA_DIR/IM/data $RESULTS_DIR/data_complex"
execute "fslcpgeom $SORTED_DATA_DIR/RE/data $RESULTS_DIR/data_complex"
execute "fslsplit $SORTED_DATA_DIR/RE/data $SORTED_DATA_DIR/RE/TE"
execute "fslsplit $SORTED_DATA_DIR/IM/data $SORTED_DATA_DIR/IM/TE"

else
# retrieve complex data from MAG and PHASE data
execute "$EXEC_DIR/prepare_phase.py $SORTED_DATA_DIR/PHASE/data.nii.gz $SORTED_DATA_DIR/PHASE/data_scaled.nii.gz"
execute "fslcomplex -complexpolar $SORTED_DATA_DIR/MAG/data $SORTED_DATA_DIR/PHASE/data_scaled $RESULTS_DIR/data_complex"
execute "fslcpgeom $SORTED_DATA_DIR/MAG/data $RESULTS_DIR/data_complex"
execute "$EXEC_DIR/dephase_slices.py $RESULTS_DIR/data_complex.nii.gz  $RESULTS_DIR/data_complex_deph.nii.gz"
execute "fslcomplex -realphase $RESULTS_DIR/data_complex_deph $SORTED_DATA_DIR/PHASE/data_scaled_deph"
execute "fslcpgeom $SORTED_DATA_DIR/MAG/data $SORTED_DATA_DIR/PHASE/data_scaled_deph"
execute "fslsplit $SORTED_DATA_DIR/PHASE/data_scaled_deph $SORTED_DATA_DIR/PHASE/TE"

fi

fi

########### BRAIN EXTRACTION
if [ $DO_EXTRACTION = 1 ]; then

echo "Brain extraction and normalization"
echo "----------------------------------"

# brain extraction
execute "bet $RESULTS_DIR/T1.nii.gz $RESULTS_DIR/T1_brain -m -R"

#execute "fslroi $SORTED_DATA_DIR/MAG/data $RESULTS_DIR/GRE0 0 1"
#execute "bet $RESULTS_DIR/GRE0.nii.gz $RESULTS_DIR/GRE0_brain -m -R"

fslroi $SORTED_DATA_DIR/MAG/data $RESULTS_DIR/GRE 0 4
fslmaths $RESULTS_DIR/GRE -sqr -Tmean -sqrt $RESULTS_DIR/GRE0
execute "bet $RESULTS_DIR/GRE0.nii.gz $RESULTS_DIR/GRE0_brain -m -R"

# erode mask
execute "fslmaths $RESULTS_DIR/GRE0_brain_mask.nii.gz -ero -kernel sphere 2 $RESULTS_DIR/GRE0_brain_mask.nii.gz"

# normalize and find matrix (flirt to t1 and fnirt to normal space)
mkdir $RESULTS_DIR/xfm

# T1 to GRE0
execute "flirt -in $RESULTS_DIR/T1_brain -ref $RESULTS_DIR/GRE0_brain -omat $RESULTS_DIR/xfm/T1toGRE0.mat -dof 6"
execute "convert_xfm -omat $RESULTS_DIR/xfm/GRE0toT1.mat -inverse $RESULTS_DIR/xfm/T1toGRE0.mat"

# T1 to STANDARD
execute "flirt -ref $MNI_BRAIN -in $RESULTS_DIR/T1_brain -omat $RESULTS_DIR/xfm/T1toMNI.mat -o $RESULTS_DIR/T1_norm_linear"
execute "fnirt --ref=$MNI --refmask=$MNI_BRAIN_MASK_DIL --in=$RESULTS_DIR/T1 --aff=$RESULTS_DIR/xfm/T1toMNI.mat --cout=$RESULTS_DIR/xfm/T1toMNIwarp" #--config=T1_2_MNI152_2mm"
execute "applywarp --ref=$MNI --in=$RESULTS_DIR/T1 --warp=$RESULTS_DIR/xfm/T1toMNIwarp --out=$RESULTS_DIR/T1_norm"

# GRE0 to STANDARD
execute "convertwarp --ref=$MNI --warp1=$RESULTS_DIR/xfm/T1toMNIwarp --premat=$RESULTS_DIR/xfm/GRE0toT1.mat --relout --out=$RESULTS_DIR/xfm/GRE0toMNIwarp"
execute "applywarp --ref=$MNI --warp=$RESULTS_DIR/xfm/GRE0toMNIwarp --in=$RESULTS_DIR/GRE0 --out=$RESULTS_DIR/GRE0_norm"

# STANDARD to GRE0
execute "invwarp --ref=$RESULTS_DIR/GRE0 --warp=$RESULTS_DIR/xfm/GRE0toMNIwarp --out=$RESULTS_DIR/xfm/MNItoGRE0warp"
fi

########### SEGMENTATION OF STRUCTURES
if [ $DO_SEGMENTATION = 1 ]; then
echo "Segmentation of structures"
echo "--------------------------"

#mkdir $RESULTS_DIR/FIRST
#execute "run_first_all -i $RESULTS_DIR/T1 -o $RESULTS_DIR/FIRST/seg -s $STRUCTURES"

#execute "mv $RESULTS_DIR/FIRST/seg_all_fast_firstseg.nii.gz $RESULTS_DIR/FIRST/T1_structures.nii.gz"
#execute "mv $RESULTS_DIR/FIRST/seg_all_fast_origsegs.nii.gz $RESULTS_DIR/FIRST/T1_structures4D.nii.gz"

# register structures to GRE0 map
#execute "flirt -in $RESULTS_DIR/FIRST/T1_structures.nii.gz -ref $RESULTS_DIR/GRE0_brain -interp nearestneighbour -init $RESULTS_DIR/xfm/T1toGRE0.mat -applyxfm -o $RESULTS_DIR/FIRST/GRE0_structures.nii.gz"
#execute "flirt -in $RESULTS_DIR/FIRST/T1_structures4D.nii.gz -ref $RESULTS_DIR/GRE0_brain -interp nearestneighbour -init $RESULTS_DIR/xfm/T1toGRE0.mat -applyxfm -o $RESULTS_DIR/FIRST/GRE0_structures4D.nii.gz"

# binarize for visualization
#execute "fslmaths $RESULTS_DIR/FIRST/GRE0_structures.nii.gz -bin $RESULTS_DIR/FIRST/GRE0_structures_mask.nii.gz"
#
# make a mask with voxels with signal under threshold
#if [ $CALC_EXCLUSION = 1 ]; then
#    execute "fslmaths $SORTED_DATA_DIR/MAG/data.nii.gz -thr $THR -bin -Tmean -mul $ECHOS -thr $THR_ECHOS -bin -sub 1 -mul -1 $RESULTS_DIR/exclusion_mask.nii.gz"
#    execute "fslmaths $RESULTS_DIR/PD.nii.gz -uthr $PD_THR -bin $RESULTS_DIR/exclusion_mask.nii.gz"
#fi

# calculate the inverted exclusion mask that we will use to mask the data
#execute "fslmaths $RESULTS_DIR/exclusion_mask.nii.gz -sub 1 -mul -1  $RESULTS_DIR/exclusion_mask_inv.nii.gz"

# remove excluded voxels from masks
#execute "fslmaths $RESULTS_DIR/FIRST/GRE0_structures4D.nii.gz -mas $RESULTS_DIR/exclusion_mask_inv.nii.gz -thr 0 $RESULTS_DIR/FIRST/GRE0_structures4D.nii.gz"

# remove boundaries from the structures
#execute "fslmaths $RESULTS_DIR/FIRST/T1_structures4D.nii.gz -uthr 100 $RESULTS_DIR/FIRST/T1_structures4D_no_bound.nii.gz"
#execute "fslmaths $RESULTS_DIR/FIRST/GRE0_structures4D.nii.gz -uthr 100 $RESULTS_DIR/FIRST/GRE0_structures4D_no_bound.nii.gz"

# measure structure volume
#echo "SUBJECT,$STRUCTURES" > $RESULTS_DIR/volumes.txt
#echo "$SUBJECT,`$EXEC_DIR/structure_volume.py $RESULTS_DIR/FIRST/GRE0_structures4D.nii.gz`" >> $RESULTS_DIR/volumes.txt

# segment CSF and WM, and register to GRE0
mkdir $RESULTS_DIR/FAST
execute "fast -o $RESULTS_DIR/FAST/FAST -g $RESULTS_DIR/T1_brain"
execute "flirt -in $RESULTS_DIR/FAST/FAST_seg_0 -ref $RESULTS_DIR/GRE0_brain -interp nearestneighbour -init $RESULTS_DIR/xfm/T1toGRE0.mat -applyxfm -o $RESULTS_DIR/FAST/GRE0_CSF"
execute "flirt -in $RESULTS_DIR/FAST/FAST_seg_2 -ref $RESULTS_DIR/GRE0_brain -interp nearestneighbour -init $RESULTS_DIR/xfm/T1toGRE0.mat -applyxfm -o $RESULTS_DIR/FAST/GRE0_WM"

# erode CSF and WM masks
execute "fslmaths $RESULTS_DIR/FAST/GRE0_CSF -kernel 2D -ero  $RESULTS_DIR/FAST/GRE0_CSF"
execute "fslmaths $RESULTS_DIR/FAST/GRE0_WM -kernel 2D -ero  $RESULTS_DIR/FAST/GRE0_WM"
fi

########### QSM ANALYSIS
if [ $DO_QSM = 1 ]; then
echo "QSM analysis"
echo "------------"

IMAGING_FREQ=`cat $SORTED_DATA_DIR/imaging_freq.txt`
echo "Imaging Frequency = $IMAGING_FREQ"

# call the QSM analysis tool
matlab -nodesktop -nosplash -r "addpath $MEDI_TOOLBOX_PATH; addpath $RESHARP_PATH; addpath $MATLAB_FSL_PATH; QSMprocessing $RESULTS_DIR/data_complex.nii.gz $RESULTS_DIR/GRE0_brain_mask.nii.gz $IMAGING_FREQ $SORTED_DATA_DIR/TEs.txt $RESULTS_DIR/QSM.nii.gz $RESULTS_DIR/background_field.nii.gz $RESULTS_DIR; exit;"
execute "fslcpgeom $RESULTS_DIR/GRE0.nii.gz $RESULTS_DIR/QSM.nii.gz"

## clean up 
rm $RESULTS_DIR/RDF.mat

fi


########### QSM REFERENCING
if [ $DO_QSM_REFERENCING = 1 ]; then
echo "QSM referencing"
echo "------------"

# obtain reference region
execute "applywarp --ref=$RESULTS_DIR/GRE0 --warp=$RESULTS_DIR/xfm/MNItoGRE0warp --in=$REF_POINTS --out=$RESULTS_DIR/GRE0_ref_points"
execute "$EXEC_DIR/grow_roi.py $RESULTS_DIR/GRE0_ref_points.nii.gz $RESULTS_DIR/FAST/GRE0_WM.nii.gz $GROW_VOXELS $RESULTS_DIR/ref_mask.nii.gz"

echo "Using $REFERENCE as reference."

# calculate average value from the reference mask
execute "fslmaths $RESULTS_DIR/QSM -mas $RESULTS_DIR/ref_mask.nii.gz $RESULTS_DIR/QSM_masked"
execute "fslmaths $RESULTS_DIR/GRE0 -mas $RESULTS_DIR/ref_mask.nii.gz $RESULTS_DIR/GRE0_masked"

MASK_VOL=`fslstats $RESULTS_DIR/ref_mask.nii.gz -V | cut -d' ' -f1`
REF_AVERAGE=`fslstats $RESULTS_DIR/QSM_masked -M | cut -d' ' -f1` 
REF_SD=`fslstats $RESULTS_DIR/QSM_masked -S | cut -d' ' -f1` 
REF_MAG_AVERAGE=`fslstats $RESULTS_DIR/GRE0_masked -M | cut -d' ' -f1` 
REF_MAG_SD=`fslstats $RESULTS_DIR/GRE0_masked -S | cut -d' ' -f1` 
echo "Mask volume: $MASK_VOL voxels"
echo "SUBJECT,VOLUME,AVERAGE,SD,MAG_AVERAGE,MAG_SD" > $RESULTS_DIR/referenceQSM.txt
echo "$SUBJECT,$MASK_VOL,$REF_AVERAGE,$REF_SD,$REF_MAG_AVERAGE,$REF_MAG_SD" >> $RESULTS_DIR/referenceQSM.txt

# subtract reference value and normalize
execute "fslmaths $RESULTS_DIR/QSM -sub $REF_AVERAGE $RESULTS_DIR/QSM_ref"

# register QSM map to T1 image 
execute "flirt -in $RESULTS_DIR/QSM_ref.nii.gz -ref $RESULTS_DIR/T1_brain -init $RESULTS_DIR/xfm/GRE0toT1.mat -applyxfm -o $RESULTS_DIR/QSM_toT1.nii.gz"

# normalize
execute "applywarp --ref=$MNI --in=$RESULTS_DIR/QSM_ref --warp=$RESULTS_DIR/xfm/GRE0toMNIwarp --out=$RESULTS_DIR/QSM_norm"

# extract values from phase map
# echo "SUBJECT,$STRUCTURES" > $RESULTS_DIR/QSM.txt
# echo "$SUBJECT,`$EXEC_DIR/extract_values.py $RESULTS_DIR/QSM_ref.nii.gz $RESULTS_DIR/FIRST/GRE0_structures4D${STRUCTURES_SUFFIX}.nii.gz`" >> $RESULTS_DIR/QSM.txt
# execute "$EXEC_DIR/extract_voxel_values.py $RESULTS_DIR/QSM_ref.nii.gz $RESULTS_DIR/FIRST/GRE0_structures4D${STRUCTURES_SUFFIX}.nii.gz $STRUCTURES > $RESULTS_DIR/QSMVoxels.txt"
fi


########### RELAXOMETRY ANALYSIS
if [ $DO_RELAXOMETRY = 1 ]; then
echo "Relaxometry analysis"
echo "--------------------"

# r2star analysis
execute "$EXEC_DIR/relaxometry.py $SORTED_DATA_DIR/MAG/data.nii.gz $RESULTS_DIR/GRE0_brain_mask.nii.gz $SORTED_DATA_DIR/TEs.txt $RELAXOMETRY_CONSTANT $RESULTS_DIR/PD.nii.gz $RESULTS_DIR/r2star.nii.gz $RESULTS_DIR/relaxErr.nii.gz"

# invert to get T2star
execute "fslmaths $RESULTS_DIR/GRE0_brain_mask.nii.gz -div $RESULTS_DIR/r2star.nii.gz -mas $RESULTS_DIR/GRE0_brain_mask.nii.gz $RESULTS_DIR/T2star"

# normalize r2star map
execute "applywarp --ref=$MNI --in=$RESULTS_DIR/r2star --warp=$RESULTS_DIR/xfm/GRE0toMNIwarp --out=$RESULTS_DIR/r2star_norm"

# register r2star map to T1 image 
execute "flirt -in $RESULTS_DIR/r2star.nii.gz -ref $RESULTS_DIR/T1_brain -init $RESULTS_DIR/xfm/GRE0toT1.mat -applyxfm -o $RESULTS_DIR/r2star_toT1.nii.gz"

fi

########### FREESURFER ANALYSIS

if [ $DO_FREESURFER = 1 ]; then

echo "Running freesurfer analysis"
echo "--------------"
#rm -r $FS_ANALYSIS_DIR/$SUBJECT
#recon-all -subject $SUBJECT -i $RESULTS_DIR/T1.nii.gz -sd $FS_ANALYSIS_DIR -all
execute "mri_convert $RESULTS_DIR/r2star_toT1.nii.gz $RESULTS_DIR/r2star_toT1.mgz"

# the aseg is in conformed space, need to have it in T1 space
execute "mri_vol2vol --mov $FS_ANALYSIS_DIR/$SUBJECT/mri/aparc+aseg.mgz --targ $RESULTS_DIR/r2star_toT1.mgz  --nearest --regheader --o $RESULTS_DIR/aparc+aseg_toT1.mgz" 

execute "mri_convert $RESULTS_DIR/QSM_toT1.nii.gz $RESULTS_DIR/QSM_toT1.mgz"

execute "mri_segstats --id $FS_LABELS --seg $RESULTS_DIR/aparc+aseg_toT1.mgz \
   --seg-erode 1 \
   --robust $ROBUST \
   --ctab $FREESURFER_HOME/FreeSurferColorLUT.txt \
   --i $RESULTS_DIR/QSM_toT1.mgz \
   --sum $FS_ANALYSIS_DIR/$SUBJECT/stats/QSM.stats"
   
execute "mri_segstats --id $FS_LABELS --seg $RESULTS_DIR/aparc+aseg_toT1.mgz \
   --seg-erode 1 \
   --robust $ROBUST \
   --ctab $FREESURFER_HOME/FreeSurferColorLUT.txt \
   --i $RESULTS_DIR/r2star_toT1.mgz \
   --sum $FS_ANALYSIS_DIR/$SUBJECT/stats/r2star.stats"

execute "mri_segstats --id $FS_LABELS --seg $RESULTS_DIR/aparc+aseg_toT1.mgz \
   --ctab $FREESURFER_HOME/FreeSurferColorLUT.txt \
   --sum $FS_ANALYSIS_DIR/$SUBJECT/stats/volume.stats"


SUBJECTS_DIR=$FS_ANALYSIS_DIR
mri_vol2surf --interp nearest --cortex --mov $RESULTS_DIR/QSM_toT1.mgz --regheader $SUBJECT --hemi lh --out $FS_ANALYSIS_DIR/$SUBJECT/surf/lh.QSM.mgh --projfrac-avg 0.1 0.3 0.1

mri_vol2surf --interp nearest --cortex --mov $RESULTS_DIR/QSM_toT1.mgz --regheader $SUBJECT --hemi rh --out $FS_ANALYSIS_DIR/$SUBJECT/surf/rh.QSM.mgh --projfrac-avg 0.1 0.3 0.1

mri_vol2surf --interp nearest --cortex --mov $RESULTS_DIR/r2star_toT1.mgz --regheader $SUBJECT --hemi lh --out $FS_ANALYSIS_DIR/$SUBJECT/surf/lh.r2star.mgh --projfrac-avg 0.1 0.3 0.1

mri_vol2surf --interp nearest --cortex --mov $RESULTS_DIR/r2star_toT1.mgz --regheader $SUBJECT --hemi rh --out $FS_ANALYSIS_DIR/$SUBJECT/surf/rh.r2star.mgh --projfrac-avg 0.1 0.3 0.1

fi
