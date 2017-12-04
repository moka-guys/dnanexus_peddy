# dnanexus_peddy v 1.0.0

## What does this app do?
This app runs peddy (https://github.com/brentp/peddy) to perform a run wide QC checking that the assigned gender matches the sample and that the run does not contain duplicate samples. It uses the sample metadata contained within the samples filenames plus the vcf files created by the pipeline.  

This app uses a release of peddy from https://github.com/moka-guys/peddy

## What are typical use cases for this app?
This app should be performed after each run. It can be run automagically using the --depends-on flag or manually.

## What data are required for this app to run?
A project number is passed to the app as a parameter.
This project must have a folder 'QC' within the root of the project.
The filename of each sample must include the gender as 'M' or 'F' deliminated by underscores.

## What does this app output?
Several files prefixed with peddy_ and the run number (*) are produced. MultiQC uses 4 of these files:
1. peddy_*.peddy.ped
2. peddy_*.het_check.csv
3. peddy_*.ped_check.csv
4. peddy_*.sex_check.csv

The rest are unused by the pipeline:

5. peddy_*.background_pca.json
6. peddy_*.het_check.png
7. peddy_*.html
8. peddy_*.pca_check.png
9. peddy_*.ped_check.png
10. peddy_*.ped_check.rel-difference.csv
11. peddy_*.sex_check.png
12. peddy_*.vs.html

The outputs are placed in /QC/multiqc

## How does this app work?
* The app parses the file names to determine the sex assigned to each of the samples and creates a fam file (https://www.cog-genomics.org/plink2/formats#fam) containing this information.  It then creates a merged vcf from the run's 'vcfs and passes the merged vcf and fam file to peddy.  peddy checks that the assigned gender matches the sample and for duplicate samples and saves this data in /QC/multiqc so that the MultiQC app can include this info in the end of the run report.

## What are the limitations of this app
The degree of functionality that peddy provides depends upon the metadata available. 
The project which peddy is run on must be shared with the user mokaguys.
Requires bcftools to be installed on the server.
Requires peddy (https://github.com/brentp/peddy).

## This app was made by Viapath Genome Informatics# dnanexus_peddy v 1.0.0

## What does this app do?
This app runs peddy (https://github.com/brentp/peddy) to perform a run wide QC checking that the assigned gender matches the sample and that the run does not contain duplicate samples. It uses the sample metadata contained within the samples filenames plus the vcf files created by the pipeline.  

This app uses a release of peddy from https://github.com/moka-guys/peddy

## What are typical use cases for this app?
This app should be performed after each run. It can be run automagically using the --depends-on flag or manually.

## What data are required for this app to run?
A project number is passed to the app as a parameter.
This project must have a folder 'QC' within the root of the project.
The filename of each sample must include the gender as 'M' or 'F' deliminated by underscores.

## What does this app output?
Several files prefixed with peddy_ and the run number (*) are produced. MultiQC uses 4 of these files:
1. peddy_*.peddy.ped
2. peddy_*.het_check.csv
3. peddy_*.ped_check.csv
4. peddy_*.sex_check.csv

The rest are unused by the pipeline:

5. peddy_*.background_pca.json
6. peddy_*.het_check.png
7. peddy_*.html
8. peddy_*.pca_check.png
9. peddy_*.ped_check.png
10. peddy_*.ped_check.rel-difference.csv
11. peddy_*.sex_check.png
12. peddy_*.vs.html

The outputs are placed in /QC/multiqc

## How does this app work?
* The app parses the file names to determine the sex assigned to each of the samples and creates a fam file (https://www.cog-genomics.org/plink2/formats#fam) containing this information.  It then creates a merged vcf from the run's 'vcfs and passes the merged vcf and fam file to peddy.  peddy checks that the assigned gender matches the sample and for duplicate samples and saves this data in /QC/multiqc so that the MultiQC app can include this info in the end of the run report.

## What are the limitations of this app
The degree of functionality that peddy provides depends upon the metadata available. 
The project which peddy is run on must be shared with the user mokaguys.
Requires bcftools to be installed on the server.
Requires peddy (https://github.com/brentp/peddy).

## This app was made by Viapath Genome Informatics
