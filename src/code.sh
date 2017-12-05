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

# Note: vcfs must be compressed using bgzip/bcftools and have an index produced by tabix/bfctools

############### Code for Peddy App ###############

# The following line causes bash to exit at any point if there is any error
# and to output each line as it is executed -- useful for debugging
set -e -x -o pipefail

############### Installations ###############

# Install programs required for the app (peddy and bcftools) using conda.
function install_app_dependencies {
    # Install Miniconda on worker
    bash $HOME/Miniconda2-latest-Linux-x86_64.sh -b -p $HOME/Miniconda
    # Add conda binaries to PATH variable
    export PATH="$HOME/Miniconda/bin:$PATH"
    # Update conda and add 'bioconda' channel. Peddy and bcftools are installed from this channel.
    conda update -y conda
    conda config --add channels bioconda
    # Install bcftools and peddy
    conda install -y bcftools peddy
}

############### Functions ###############

# Renames sample in vcf header from 1 to the filename. As currently all
# vcfs produced by pipeline has Sample header set to 1
function rename_vcf_header {
    # Use mktemp to create a temp file
    tmp=$(mktemp -t temp.XXX)
    # Copy vcf file name called by function into temp file. VCF file extension is removed using
    # ${string%%substring}, where '%%' deletes the longest match of 'substring' the end of $string
    echo ${1%%\.*} > $tmp
    # Use bcftools to change sample name in header to match file name
    bcftools reheader -s $tmp $1 > temp.$1
    mv temp.$1 $1
    # Use bcftools to create index for updated vcf file which is required for 
    # bcftools merge
    bcftools index $1
}

# Run rename_vcf_header function on all vcf files in the working directory (/home/dnanexus)
function batch_rename_vcf_header {
    for files in *.vcf.gz
        do
            rename_vcf_header $files
        done
}

# Create a single FAM file that describes the pedigree of all samples.
# FAM files are tab-delimited files with a record for each of the following headings:
#     Family_ID [string], Individual_ID [string], Father_ID [string], 
#     Mother_ID [string], Sex [integer], Phenotype (optional) [float]
# Note: Father_ID, Mother_ID, or Sex of 0 = Unknown
function create_fam_file {
    # Set string with FAM file name using project folder title
    fam_file="ped.${project_for_peddy}.fam"
    # Create empty fam file. The null operator (:) is redirected to a file, named using $fam_file.
    # This ensures an empty FAM file is created for writing to, even if it already exists
    :> $fam_file

    # Loop over vcfs and extract data for fam file entry
    for file in *vcf.gz; do
        # Extract sample sex from file name
        sex=$(echo $file | sed -n 's/.*_\([M,F]\)_.*/\1/p')
        # Convert into sex code used by peddy
        # Sex code ('1' = male, '2' =female. '0' = unknown)
        if [[ $sex == "M" ]]; then
            sex_code="1"
        elif [[ $sex == "F" ]]; then
            sex_code="2"
        else
            sex_code="0" #Unknown sex
        fi
        # Extract sample name from file name
        sample_name=${file%%\.*} # TODO: Currently just uses the file name, use actual sample name?
        # Generate 10-character random string as a unique family ID for each vcf:
        # `cat/dev/urandom` creates a pseudo-random stream of characters, which is limited to alpha-
        # numeric characters using `tr -dc '[:alnum:]', and limited to 10 characters using `head -c 10`
        famid=$(echo $(cat /dev/urandom | tr -dc '[:alnum:]' | head -c 10))
        # Write out line to FAM file in tab delimited format
        echo -e "$famid\t$sample_name\t0\t0\t$sex_code\t2" >> $fam_file
    done
}

# Create a merged VCF from all the VCFs listed in the specified folder using bcftools 
# (https://vcftools.github.io/htslib.html#merge).
# TODO: Specify merged vcf name using project name rather than hard coding
function merge_vcfs {
    #merge all vcfs in separate vcf (options: -O z compressed vcf, -O v for uncompressed)
    bcftools merge -O z -o merged.vcf.gz *.vcf.gz
    bcftools index merged.vcf.gz
}

############### Run Program ###############

main(){
# Detect when variant calling has finished before running script:
    #TODO: Copy-and-paste relevant code from MultiQC App which detects when run has
    #finished

# Read the api key as a variable
API_KEY=$(cat '/home/dnanexus/auth_key')

# Download the desired inputs. Use the input $project_for_peddy to build the path to look in.
dx download $project_for_peddy:output/*vcf.gz --auth $API_KEY
dx download $project_for_peddy:output/*vcf.gz.tbi --auth $API_KEY

# Run function to install bcftools and peddy on linux worker
install_app_dependencies

# Run functions to prepare files for input into peddy
create_fam_file
batch_rename_vcf_header
merge_vcfs

# Run Peddy using the merged VCF and the previously created ped/fam file saving
# the output in the QC folder alongside the output of other QC apps.
# TODO: add project name to prefix
peddy --plot -p 4 --prefix ped merged.vcf.gz $fam_file #TODO: remove hard coded vcf name

# Create directories for app outputs to be uploaded to dna nexus.
mkdir -p $HOME/out/peddy/QC/peddy_extra
# Move files required by MultiQC to the QC folder
mv ped.*{peddy.ped,het_check.csv,ped_check.csv,sex_check.csv} $HOME/out/peddy/QC/
# Move all other files to the foler QC/peddy_extra
mv ped* $HOME/out/peddy/QC/peddy_extra

# Upload all output files to the worker. As per the outputSpec field in the dxapp.json, all files
# and folders in /home/dnanexus/out/peddy/ are uploaded to the project folder's root directory.
dx-upload-all-outputs

# TODO: Edit nexus workflow to ensure MultiQC App starts after this app is complete.
# TODO: Check to see if we need to output logs to loggly
}
