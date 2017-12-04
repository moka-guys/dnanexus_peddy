#!/usr/bin/env bash
#

# Purpose: provides additional QC of DNA Nexus runs by adding Peddy
# (https://github.com/brentp/peddy) to the pipeline and making the output 
# available to MultiQC for display to the end-user. 
# Specifically this app:
# i) Adds a sex check by matching the sex recorded for the sample to the 
# sex predicted by Peddy.
# ii) Adds a check to identify any duplicate samples in the run.

# Additionally Peddy provides information on the 'relatedness' of samples which
# could be used as a check that trios are correctly labelled. 

# vcfs must be compressed using bgzip/bcftools and have an index produced by tabix/bfctools

############### Code for Peddy App ###############

# The following line causes bash to exit at any point if there is any error
# and to output each line as it is executed -- useful for debugging
set -e -x -o pipefail

############### Functions ###############

#TODO Specify folder where VCFs are located and update functions below

# Renames sample in vcf header from 1 to the filename. As currently all
# vcfs produced by pipeline has Sample header set to 1

function rename_vcf_header {
    # Use mktemp to create a temp file
    tmp=$(mktemp -t temp)
    # Copy vcf called by function into temp file
    echo ${1} > $tmp
    # Use bcftools to change sample name in header to match file name
    bcftools reheader -s $tmp $1 > temp.$1
    mv temp.$1 $1
    # Use bcftools to create index for updated vcf file which is required for 
    # bcftools merge
    bcftools index $1
}

# Run rename_vcf_header function on all vcf files in folder
# TODO allow path to folder to be set when calling function
function batch_rename_vcf_header {
    for files in *.vcf.gz
        do
            rename_vcf_header $files
        done
}

# Creates fam file for the all vcf files in directory TODO specify folder
# TODO insert FAM format here

function create_fam_file {
    # Create a fam file that describes the pedigree of the data 
    fam_file="place_name.fam" #TODO: replace hard code - generate name from project folder  name
    touch $fam_file #TODO check if Fam file already exists
    # Extract data from vcf and add to fam file
        for file in *vcf.gz
            do
                #Extract sample sex from file name
                sex=$(echo $file | sed -n 's/.*_\([M,F]\)_.*/\1/p')
                # Convert into sex code used by peddy
                # Sex code ('1' = male, '2' =female. '0' = unknown)
                if [[ $sex == "M" ]]
                then    
                    sex_code="1"
                elif [[ $sex == "F" ]]
                then
                    sex_code="2"
                else
                    sex_code="0" #Unknown sex
                fi
                #Extract sample name from file name
                sample_name=$file #Currently just uses the file name - can alter this later
                # Write out line to file in tab delimited format
                echo -e "$file\t$sample_name\t0\t0\t$sex_code\t2" >> $fam_file
            done
}

# Create a merged VCF from all the VCFs listed in the specified folder using bcftools 
# (https://vcftools.github.io/htslib.html#merge) and generate a 
# sensible name for the merged VCF.

#TODO Specify merged vcf name using project name rather than hard coding

function merge_vcfs {
    #merge all vcfs in separate vcf (options: -O z compressed vcf, -O v for uncompressed)
    bcftools merge -O z -o merged.vcf.gz *.vcf.gz
    bcftools index merged.vcf.gz
}

############### Run Program ###############

# Detect when variant calling has finished before running script:

    #TODO: Copy-and-paste relevant code from MultiQC App which detects when run has
    #finished

#read the api key as a variable
API_KEY=$(cat '/home/dnanexus/auth_key')

# download the desired inputs. Use the input $project_for_multiqc to build the path to look in.
dx download $project_for_multiqc:output/*vcf.gz --auth $API_KEY
dx download $project_for_multiqc:output/*vcf.gz.tbi --auth $API_KEY

# Run functions to prepare files for input into peddy
create_fam_file
batch_rename_vcf_header
merge_vcfs

# Run Peddy using the merged VCF and the previously created ped/fam file saving
# the output in the QC folder alongside the output of other QC apps
#TODO direct output to QC folder
#TODO add project name to prefix
peddy --plot -p 4 --prefix ped merged.vcf.gz $fam_file #TODO: remove hard coded vcf name

# Once Peddy App has finished start Multic QC App
    
    # Add code here to accomplish this

#TODO: Check to see if we need to output logs to loggly








    




