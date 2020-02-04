#!/usr/bin/env bash
# Provides additional QC of DNA Nexus workflows by adding Peddy (https://github.com/brentp/peddy)
# to the QC pipeline and making the output available to MultiQC for display to the end-user.
# i) Adds a sex check by matching the sex recorded for the sample to the sex predicted by Peddy.
# ii) Adds a check to identify any duplicate samples in the run.
# iii) Provides information on the 'relatedness' of samples to identify incorrectly labelled trios.
# Note: vcfs must be compressed using bgzip/bcftools and have an index produced by tabix/bfctools

############### Code for Peddy App ###############

# The following line causes bash to exit at any point if there is any error
# and to output each line as it is executed -- useful for debugging
set -e -x -o pipefail

############### Functions ###############

# Extract the sample name from the VCF filename and print to stdout.
function get_sample_name {
    # Usage: get_sample_name "file.vcf.gz"

    # Assign vcf filename to a variable.
    local vcf_file=$1
    # Remove extensions from VCF filename using ${string%%substring}. Here, '%%' deletes the
    # longest match of 'substring' from the end of 'string'. Here, the substring removed contains the
    # first '.' and all following characters in the filename. This is required as peddy does not
    # accept the '.' character in sample names.
    local vcf_file_cut_extension=${vcf_file%%\.*}
    # Remove trailing '_001' from the end of vcf filename. This done using the `sed` substitution
    # command and is required as MultiQC expects sample names without _001. See multiqc YAML in app:
    # dnanexus_multiqc/resources/home/dnanexus/.
    local vcf_file_cut_001=$(echo ${vcf_file_cut_extension} | sed s'/_001$//')
    # Return cleaned sample name by printing to stdout
    echo $vcf_file_cut_001
}

# Rename sample name in the vcf header to the filename (without extensions) using `bcftools reheader`.
# This is required as VCFs produced by mokapipe pipeline have a default sample name of '1'.
#
# Usage: rename_vcf_header file.vcf.gz
#
# To rename samples in a vcf using `bcftools reheader`, a file containing new sample names must
# be provided using the `-s` flag. Here, a temporary file containing the vcf filename (without
# extensions) is created for this purpose.
function rename_vcf_header {

    # Assign vcf filename to a variable. This is passed as the first function argument, accessed
    # from the variable $1.
    vcf_file=$1

    # Extract sample name from VCF filename using `get_sample_name` function and assign to variable.
    new_sample_name=$(get_sample_name $vcf_file)

    # Create a temporary file using mktemp.
    tmp=$(mktemp -t temp.XXX)

    # Write VCF filename to temp file.
    echo ${new_sample_name} > $tmp

    # Use bcftools v1.6 docker container to rename the sample name in vcf header, using the sample name in the temp file.
    # By default `bcftools reheader` writes the edited VCF to the console, but here the result is
    # redirected to the file temp.$vcf_file.
    # -v /:/data mounts the root of the dnanexus worker to /data within the docker container to allow file access

    dx-docker run -v /:/data quay.io/biocontainers/bcftools:1.6--1 bcftools reheader -s /data/$tmp /data/${PWD}/$vcf_file > temp.$vcf_file

    # Rename edited VCF using the name of the original VCF, deleting the original in the process.
    mv temp.$vcf_file $vcf_file

    # Use bcftools v1.6 docker container to create an index for the updated vcf file which will be required by
    # `bcftools merge`. The -t flag indexes the file using tabix.
    # -v /:/data mounts the root of the dnanexus worker to /data within the docker container to allow file access
    dx-docker run -v /:/data quay.io/biocontainers/bcftools:1.6--1 bcftools index -t /data/${PWD}/$vcf_file
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
    # Create empty fam file to write to.
    touch $fam_file
    # Set a counter to use as the family ID. This will correspond with the line number for each record.
    fam_ID=0

    # Loop over vcfs and extract data for fam file entry
    for file in *vcf.gz; do

        # Extract sample sex from file name.
        #
        # The filename is piped to the `sed` substitution command, which has the syntax
        # 's/regular_expression/substitution_string/modifier'.
        # The regular expression used is .*_\([M,F])\)_.* and can be translated as follows:
        #   Search the filename for an M or F character using '[]'. The character must be flanked by
        #   underscores which can then be preceeded or followed by any number of any character
        #   ('.*_' and '_.*' ). Use escaped parthenses '\(' and '\)' to capture the M or F character.
        # The entire input filename string is then substituted for the captured character using the
        # backreference syntax (\1). Finally, the modifier 'p' instructs `sed` to print out the
        # subsituted string, which is assigned to $sex.
        #
        # If no sample sex string is found, the $sex variable is empty and sample sex is set to 'Unknown'.
        sex=$(echo $file | sed -n 's/.*_\([M,F]\)_.*/\1/p')

        # Convert $sex to the sex code used by peddy. Sex code '1' = male, '2' =female and '0' = unknown.
        if [[ $sex == "M" ]]; then
            sex_code="1"
        elif [[ $sex == "F" ]]; then
            sex_code="2"
        else
            sex_code="0"
        fi

        # Extract sample name from VCF filename using `get_sample_name` and assign to variable.
        sample_name=$(get_sample_name $file)
        # Increment fam_ID number for generic family ID record.
        fam_ID=$((fam_ID+1))
        # Write out line to FAM file in tab delimited format
        echo -e "FAM$fam_ID\t$sample_name\t0\t0\t$sex_code\t" >> $fam_file
    done
}

# Create a merged VCF from all the VCFs listed in the specified folder using bcftools 
# (https://vcftools.github.io/htslib.html#merge).
function merge_vcfs {
    # Usage: merge_vcfs ${project_for_peddy}
    # Merges all VCF files in the working directory into a single VCF using `bcftools merge`.
    # The option '-O z' produces a compressed vcf, which is named using the '-o' flag.
    # The merged VCF is named using the first function argument (${1}, the DNA Nexus Project name)
    # with the suffix '_merged.vcf.gz'.
    # -v /:/data mounts the root of the dnanexus worker to /data within the docker container to allow file access
    dx-docker run -v /:/data quay.io/biocontainers/bcftools:1.6--1 bcftools merge -O z -o /data/${PWD}/${1}_merged.vcf.gz /data/${PWD}/*.vcf.gz 
    # Use bcftools v1.6 docker container to create an index of the merged VCF file, which is required by Peddy.
    # The -t flag indexes the file using tabix.
    # -v /:/data mounts the root of the dnanexus worker to /data within the docker container to allow file access
    dx-docker run -v /:/data quay.io/biocontainers/bcftools:1.6--1 bcftools index -t /data/${PWD}/${1}_merged.vcf.gz
}

############### Run Program ###############

main(){
# Read the api key as a variable
API_KEY=$(dx cat project-FQqXfYQ0Z0gqx7XG9Z2b4K43:mokaguys_nexus_auth_key)

# Download the desired inputs. Use the input $project_for_peddy to build the path to look in.
# First try to download files named *aplotyper.vcf.gz (mokawes > v1.7) - if this fails then look for refined.vcf.gz (Mokawes <1.7) 
dx download $project_for_peddy:output/*aplotyper.vcf.gz --auth $API_KEY || dx download $project_for_peddy:output/*.refined.vcf.gz --auth $API_KEY

# Run functions to prepare files for input into peddy.
# Create a single FAM file that describes the sex of all samples. Sex is read from VCF sample names,
# as '_M_' (male), '_F_' (female) or 'Unknown' if not found.
create_fam_file

# Rename sample name in each VCF file header to its filename (without extensions). Required as as VCFs 
# produced by mokapipe have a default sample name of '1'.
batch_rename_vcf_header

# Create a single merged vcf from each VCF file, supplying the project name for use as a prefix.
merge_vcfs "${project_for_peddy}"

# Run Peddy docker container using the merged VCF and the previously created ped/fam file.
# -v /:/data mounts the root of the dnanexus worker to /data within the docker container to allow file access
dx-docker run -v /:/data quay.io/biocontainers/peddy:0.3.1--py27_0 /bin/bash -c "cd /data/${PWD}; peddy --plot -p 4 --prefix ped ${project_for_peddy}_merged.vcf.gz ${fam_file}" 

# Create directories for app outputs to be uploaded to dna nexus.
mkdir -p $HOME/out/peddy/QC/peddy
# Move files required by MultiQC to the QC folder
mv ped.*{peddy.ped,het_check.csv,ped_check.csv,sex_check.csv} $HOME/out/peddy/QC/
# Move all other files to the folder QC/peddy_extra. Includes the merged vcf file used to run peddy.
mv ped* *_merged.vcf.gz* $HOME/out/peddy/QC/peddy

# Upload all output files to the worker. As per the outputSpec field in the dxapp.json, all files
# and folders in /home/dnanexus/out/peddy/ are uploaded to the project folder's root directory.
dx-upload-all-outputs
}
