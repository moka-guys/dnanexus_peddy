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

# Rename sample name in the vcf header to the filename (without extension string). 
# Currently, VCFs produced by mokapipe pipeline have the sample name set to 1 in the vcf header. 
function rename_vcf_header {
    # Usage: rename_vcf_header file.vcf.gz

    # Use mktemp to create a temp file
    tmp=$(mktemp -t temp.XXX)
    # Write vcf file name to temp file. File extensions are removed using ${string%%substring}, 
    # where '%%' deletes the longest match of 'substring' from the end of $string.
    # This is required as Peddy does not accept '.' characters in sample names. 
    echo ${1%%\.*} > $tmp
    # Use bcftools to change sample name in vcf header to match file name
    bcftools reheader -s $tmp $1 > temp.$1
    mv temp.$1 $1
    # Use bcftools to create index for updated vcf file which is required for bcftools merge
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
#     Family_ID [string] \t Individual_ID [string] \t Father_ID [string] \t 
#     Mother_ID [string] \t Sex [integer] \t Phenotype (optional) [float]
# Note: Father_ID, Mother_ID, or Sex of 0 = Unknown. Individual_ID cannot be 0.
function create_fam_file {
    # Set string with FAM file name using project folder title
    fam_file="ped.${project_for_peddy}.fam"
    # Create empty fam file. The null operator (:) is redirected to a file, named using $fam_file.
    # This ensures an empty FAM file is created for writing to, even if it already exists
    :> $fam_file
    # Set a counter to use as the family ID. This will correspond with the line number for each record.
    fam_ID=0

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
        sample_name=${file%%\.* | sed -e 's/_001$//'} #Sed trims _001 from filename as Multiqc expects this - see multiqc yaml file 
        fam_ID=$((fam_ID+1))
        # Write out line to FAM file in tab delimited format
        echo -e "FAM$fam_ID\t$sample_name\t0\t0\t$sex_code\t2" >> $fam_file
    done
}

# Create a merged VCF from all the VCFs listed in the specified folder using bcftools 
# (https://vcftools.github.io/htslib.html#merge).

function merge_vcfs {
    #merge all vcfs in separate vcf (options: -O z compressed vcf, -O v for uncompressed)
    bcftools merge -O z -o "${1}_merged.vcf.gz" *.vcf.gz #Uses argument provided to function as prefix for created file
    bcftools index "${1}_merged.vcf.gz"
}

############### Run Program ###############

main(){

# Read the api key as a variable
API_KEY=$(cat '/home/dnanexus/auth_key')

# Download the desired inputs. Use the input $project_for_peddy to build the path to look in.
dx download $project_for_peddy:output/*.refined.vcf.gz --auth $API_KEY
dx download $project_for_peddy:output/*vcf.gz.tbi --auth $API_KEY

# Run function to install bcftools and peddy on linux worker
install_app_dependencies

# Run functions to prepare files for input into peddy
create_fam_file
batch_rename_vcf_header
merge_vcfs "${project_for_peddy}" #Supply project name prefix for created file

# Run Peddy using the merged VCF and the previously created ped/fam file saving
# the output in the QC folder alongside the output of other QC apps.

peddy --plot -p 4 --prefix ped "${project_for_peddy}_merged.vcf.gz" $fam_file 

# Create directories for app outputs to be uploaded to dna nexus.
mkdir -p $HOME/out/peddy/QC/peddy_extra
# Move files required by MultiQC to the QC folder
mv ped.*{peddy.ped,het_check.csv,ped_check.csv,sex_check.csv} $HOME/out/peddy/QC/
# Move all other files to the folder QC/peddy_extra
mv ped* $HOME/out/peddy/QC/peddy_extra
mv *_merged.vcf.gz* $HOME/out/peddy/QC/peddy_extra #includes index file for merged vcf

# Upload all output files to the worker. As per the outputSpec field in the dxapp.json, all files
# and folders in /home/dnanexus/out/peddy/ are uploaded to the project folder's root directory.
dx-upload-all-outputs

}
