#!/bin/bash
#title          :update
#description    :Update the index with new genomes
#author         :Fabio Cumbo (fabio.cumbo@gmail.com)
#===================================================

DATE="May 30, 2022"
VERSION="0.1.0"

# Define script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Import utility functions
source ${SCRIPT_DIR}/utils.sh

# Define default value for --nproc
NPROC=1
# Define default boundary uncertainty percentage
BOUNDARY_UNCERTAINTY_PERC=0
# Initialize CheckM completeness and contamination to default values
# Run CheckM if provided completeness is >0 or contamination is <100
CHECKM_COMPLETENESS=0
CHECKM_CONTAMINATION=100
# CheckM cannot handle a set of genomes with mixed file extensions
# Extensions of the input genomes must be standardized before running this script
# Input genome extension is forced to be fna
EXTENSION="fna"
# Dereplicate input genomes
# Use kmtricks to build the kmer matrix on the input set of genomes
# Remove genomes with identical set of kmers
DEREPLICATE=false
# Remove temporary data at the end of the pipeline
CLEANUP=false

# Parse input arguments
for ARG in "$@"; do
    case "$ARG" in
        --boundaries=*)
            # Clusters boundaries computed through the boundaries module
            BOUNDARIES="${ARG#*=}"
            # Define helper
            if [[ "${BOUNDARIES}" =~ "?" ]]; then
                printf "update helper: --boundaries=file\n\n"
                printf "\tPath to the output table produced by the boundaries module.\n"
                printf "\tIt is required in case of MAGs as input genomes only\n\n"
                exit 0
            fi
            # Check whether the input file exists
            if [[ ! -f $BOUNDARIES ]]; then
                printf "Input file does not exist!\n"
                printf "--boundaries=%s\n" "$BOUNDARIES"
                exit 1
            fi
            ;;
        --boundary-uncertainty=*)
            # Boundary uncertainty percentage
            BOUNDARY_UNCERTAINTY_PERC="${ARG#*=}"
            # Define helper
            if [[ "${BOUNDARY_UNCERTAINTY_PERC}" =~ "?" ]]; then
                printf "update helper: --boundary-uncertainty=num\n\n"
                printf "\tDefine the percentage of kmers to enlarge and reduce boundaries\n\n"
                exit 0
            fi
            # Check whether --boundary-uncertainty is an integer between 0 and 100
            if [[ ! ${BOUNDARY_UNCERTAINTY_PERC} =~ ^[0-9]+$ ]] || [[ "${BOUNDARY_UNCERTAINTY_PERC}" -lt "0" ]] || [[ "${BOUNDARY_UNCERTAINTY_PERC}" -gt "100" ]]; then
                printf "Argument --boundary-uncertainty must be a positive integer between 0 and 100\n"
                exit 1
            fi
            ;;
        --checkm-completeness=*)
            # CheckM completeness
            CHECKM_COMPLETENESS="${ARG#*=}"
            # Define helper
            if [[ "${CHECKM_COMPLETENESS}" =~ "?" ]]; then
                printf "update helper: --checkm-completeness=num\n\n"
                printf "\tInput genomes must have a minimum completeness percentage before being processed and added to the database\n\n"
                exit 0
            fi
            # Check whether --checkm-completeness is an integer
            if [[ ! ${CHECKM_COMPLETENESS} =~ ^[0-9]+$ ]] || [[ "${CHECKM_COMPLETENESS}" -gt "100" ]]; then
                printf "Argument --checkm-completeness must be a positive integer greater than 0 (up to 100)\n"
                exit 1
            fi
            ;;
        --checkm-contamination=*)
            # CheckM contamination
            CHECKM_CONTAMINATION="${ARG#*=}"
            # Define helper
            if [[ "${CHECKM_CONTAMINATION}" =~ "?" ]]; then
                printf "update helper: --checkm-contamination=num\n\n"
                printf "\tInput genomes must have a maximum contamination percentage before being processed and added to the database\n\n"
                exit 0
            fi
            # Check whether --checkm-contamination is an integer
            if [[ ! ${CHECKM_CONTAMINATION} =~ ^[0-9]+$ ]] || [[ "${CHECKM_CONTAMINATION}" -gt "100" ]]; then
                printf "Argument --checkm-completeness must be a positive integer lower than 100 (up to 0)\n"
                exit 1
            fi
            ;;
        --cleanup)
            # Remove temporary data at the end of the pipeline
            CLEANUP=true
            ;;
        --db-dir=*)
            # Database directory
            DBDIR="${ARG#*=}"
            # Define helper
            if [[ "${DBDIR}" =~ "?" ]]; then
                printf "update helper: --db-dir=directory\n\n"
                printf "\tThis is the database directory with the taxonomically organised sequence bloom trees.\n\n"
                exit 0
            fi
            # Reconstruct the full path
            DBDIR="$( cd "$( dirname "${DBDIR}" )" &> /dev/null && pwd )"/"$( basename $DBDIR )"
            # Trim the last slash out of the path
            DBDIR="${DBDIR%/}"
            # Check whether the input directory exist
            if [[ ! -d $DBDIR ]]; then
                printf "Input folder does not exist!\n"
                printf "--db-dir=%s\n" "$DBDIR"
                exit 1
            fi
            ;;
        --dereplicate)
            # Dereplicate input genomes
            DEREPLICATE=true
            ;;
        --extension=*)
            # Input genome files extension
            # It must be standardised before running this tool module
            # All the input genomes must have the same file extension
            EXTENSION="${ARG#*=}"
            # Define helper
            if [[ "${EXTENSION}" =~ "?" ]]; then
                printf "update helper: --extension=value\n\n"
                printf "\tSpecify the input genome files extension.\n"
                printf "\tAll the input genomes must have the same file extension before running this module.\n\n"
                exit 0
            fi
            # Allowed extensions: "fa", "fasta", "fna" and gzip compressed formats
            EXTENSION_LIST=("fa" "fa.gz" "fasta" "fasta.gz" "fna" "fna.gz")
            if ! echo ${EXTENSION_LIST[@]} | grep -w -q $EXTENSION; then
                printf "File extension \"%s\" is not allowed!\n" "$TYPE"
                printf "Please have a look at the helper of the --extension argument for a list of valid input file extensions.\n"
                exit 1
            fi
            ;;
        --filter-size=*)
            # Bloom filter size
            FILTER_SIZE="${ARG#*=}"
            # Define helper
            if [[ "${FILTER_SIZE}" =~ "?" ]]; then
                printf "update helper: --filter-size=num\n\n"
                printf "\tThis is the size of the bloom filters.\n\n"
                exit 0
            fi
            # Check whether --filter-size is an integer
            if [[ ! ${FILTER_SIZE} =~ ^[0-9]+$ ]] || [[ "${FILTER_SIZE}" -eq "0" ]]; then
                printf "Argument --filter-size must be a positive integer greater than 0\n"
                exit 1
            fi
            ;;
        -h|--help)
            # Print extended help
            UPDATE_HELP=true
            source ${SCRIPT_DIR}/../HELP
            exit 0
            ;;
        --input-list=*)
            # Input file with the list of paths to the new genomes
            INLIST="${ARG#*=}"
            # Define helper
            if [[ "${INLIST}" =~ "?" ]]; then
                printf "update helper: --input-list=file\n\n"
                printf "\tThis file contains the list of paths to the new genomes that will be added to the database.\n\n"
                exit 0
            fi
            # Check whether the input file exists
            if [[ ! -f $BOUNDARIES ]]; then
                printf "Input file does not exist!\n"
                printf "--input-list=%s\n" "$INLIST"
                exit 1
            fi
            ;;
        --kingdom=*)
            # Consider genomes whose lineage belong to a specific kingdom only
            KINGDOM="${ARG#*=}"
            # Define helper
            if [[ "${KINGDOM}" =~ "?" ]]; then
                printf "update helper: --kingdom=value\n\n"
                printf "\tSelect the kingdom that will be updated.\n\n"
                exit 0
            fi
            ;;
        --kmer-len=*)
            # Length of the kmers
            KMER_LEN="${ARG#*=}"
            # Define helper
            if [[ "${KMER_LEN}" =~ "?" ]]; then
                printf "update helper: --kmer-len=num\n\n"
                printf "\tThis is the length of the kmers used for building bloom filters.\n\n"
                exit 0
            fi
            # Check whether --kmer-len is an integer
            if [[ ! ${KMER_LEN} =~ ^[0-9]+$ ]] || [[ "${KMER_LEN}" -eq "0" ]]; then
                printf "Argument --kmer-len must be a positive integer greater than 0\n"
                exit 1
            fi
            ;;
        --nproc=*)
            # Max nproc for all parallel instructions
            NPROC="${ARG#*=}"
            # Define helper
            if [[ "${NPROC}" =~ "?" ]]; then
                printf "update helper: --nproc=num\n\n"
                printf "\tThis argument refers to the number of processors used for parallelizing the pipeline when possible.\n"
                printf "\tDefault: --nproc=1\n\n"
                exit 0
            fi
            # Check whether --proc is an integer
            if [[ ! $NPROC =~ ^[0-9]+$ ]] || [[ "$NPROC" -eq "0" ]]; then
                printf "Argument --nproc must be a positive integer greater than 0\n"
                exit 1
            fi
            ;;
        --taxa=*)
            # Input file with the mapping between input reference genome IDs and their taxonomic label
            TAXA="${ARG#*=}"
            # Define helper
            if [[ "${TAXA}" =~ "?" ]]; then
                printf "update helper: --taxa=file\n\n"
                printf "\tInput file with the mapping between input genome IDs and their taxonomic label.\n"
                printf "\tThis is used in case of reference genomes only \"--type=references\".\n\n"
                exit 0
            fi
            # Check whether the input file exists
            if [[ ! -f $BOUNDARIES ]]; then
                printf "Input file does not exist!\n"
                printf "--taxa=%s\n" "$TAXA"
                exit 1
            fi
            ;;
        --tmp-dir=*)
            # Temporary folder
            TMPDIR="${ARG#*=}"
            # Define helper
            if [[ "${TMPDIR}" =~ "?" ]]; then
                printf "update helper: --tmp-dir=directory\n\n"
                printf "\tPath to the folder for storing temporary data.\n\n"
                exit 0
            fi
            # Reconstruct the full path
            TMPDIR="$( cd "$( dirname "${TMPDIR}" )" &> /dev/null && pwd )"/"$( basename $TMPDIR )"
            # Trim the last slash out of the path
            TMPDIR="${TMPDIR%/}"
            ;;
        --type=*)
            # Input genomes type: references or MAGs
            TYPE="${ARG#*=}"
            # Define helper
            if [[ "${TYPE}" =~ "?" ]]; then
                printf "update helper: --type=value\n\n"
                printf "\tDefine the nature of the input genomes. Only \"references\" and \"MAGs\" are allowed.\n\n"
                exit 0
            fi
            # Allowed genome types: "references" and "MAGs"
            if [[ ! "$TYPE" = "MAGs" ]] && [[ ! "$TYPE" = "references" ]]; then
                printf "Input type \"%s\" is not allowed!\n" "$TYPE"
                printf "Please have a look at the helper of the --type argument for a list of valid genome types.\n"
                exit 1
            fi
            ;;
        *)
            printf "update: invalid option -- %s\n" "$ARG"
            exit 1
            ;;
    esac
done

printf "update version %s (%s)\n\n" "$VERSION" "$DATE"
PIPELINE_START_TIME="$(date +%s.%3N)"

check_dependencies false
if [[ "$?" -gt "0" ]]; then
    printf "Unsatisfied software dependencies!\n\n"
    printf "Please run the following command for a list of required external software dependencies:\n\n"
    printf "\t$ meta-index --resolve-dependencies\n\n"
    
    exit 1
fi

# Create temporary folder
mkdir -p $TMPDIR

# Count how many genomes in input
HOW_MANY=$(cat ${INLIST} | wc -l)
printf "Processing %s genomes\n" "${HOW_MANY}"
printf "\t%s\n\n" "${INLIST}"

# Input genomes must be quality-controlled before being added to the database
if [[ "${CHECKM_COMPLETENESS}" -gt "0" ]] && [[ "${CHECKM_CONTAMINATION}" -lt "100" ]]; then
    CHECKMTABLES="" # This is the result of the "run_checkm" function as a list of file paths separated by comma
    run_checkm $INLIST $EXTENSION $TMPDIR $NPROC
    
    # Read all the CheckM output tables and filter genomes on their completeness and contamination scores 
    # according to the those provided in input
    touch ${TMPDIR}/genomes_qc.txt
    CHECKMTABLES_ARR=($(echo $CHECKMTABLES | tr "," " "))
    for table in ${CHECKMTABLES_ARR[@]}; do
        # Skip header line with sed
        # Discard genomes according to their completeness and contamination
        sed 1d $table | while read line; do
            # Retrieve completeness and contamination of current genome
            GENOMEID="$(echo $line | cut -d$'\t' -f1)"          # Get value under column 1
            COMPLETENESS="$(echo $line | cut -d$'\t' -f12)"     # Get value under column 12
            CONTAMINATION="$(echo $line | cut -d$'\t' -f13)"    # Get value under column 13
            if [[ "$COMPLETENESS" -ge "${CHECKM_COMPLETENESS}" ]] && [[ "$CONTAMINATION" -le "${CHECKM_CONTAMINATION}" ]]; then
                # Current genome passed the quality control
                grep -w "${GENOMEID}.${EXTENSION}" ${INLIST} >> ${TMPDIR}/genomes_qc.txt
            fi
        done
    done

    # Create a new INLIST file with the new list of genomes
    INLIST=${TMPDIR}/genomes_qc.txt
    # Count how many genomes passed the quality control
    HOW_MANY=$(cat ${INLIST} | wc -l)

    printf "\t%s genomes passed the quality control\n" "${HOW_MANY}"
    printf "\t\tMinimum completeness: %s\n" "${CHECKM_COMPLETENESS}"
    printf "\t\tMaximum contamination: %s\n" "${CHECKM_CONTAMINATION}"
fi

# Use kmtricks to build a kmer matrix and compare input genomes
# Discard genomes with the same set of kmers (dereplication)
if ${DEREPLICATE}; then
    # Count how many input genomes survived in case they have been quality controlled
    HOW_MANY=$(cat ${INLIST} | wc -l)
    if [[ "${HOW_MANY}" -gt "1" ]]; then        
        GENOMES_FOF=${TMPDIR}/genomes.fof
        # Build a fof file with the list of input genomes
        while read -r genomepath; do
            GENOME_NAME="$(basename $genomepath)"
            echo "${GENOME_NAME} : $genomepath" >> ${GENOMES_FOF}
        done <$INLIST

        if [[ -f ${GENOMES_FOF} ]]; then
            printf "\nDereplicating %s input genomes\n" "${HOW_MANY}"
            # Run kmtricks to build the kmers matrix
            kmtricks_matrix_wrapper ${GENOMES_FOF} \
                                    ${TMPDIR}/matrix \
                                    ${NPROC} \
                                    ${TMPDIR}/kmers_matrix.txt
            
            # Add header to the kmers matrix
            HEADER=$(awk 'BEGIN {ORS = " "} {print $1}' ${GENOMES_FOF})
            echo "#kmer $HEADER" > ${TMPDIR}/kmers_matrix_wh.txt
            cat ${TMPDIR}/kmers_matrix.txt >> ${TMPDIR}/kmers_matrix_wh.txt
            mv ${TMPDIR}/kmers_matrix_wh.txt ${TMPDIR}/kmers_matrix.txt
            # Remove duplicate columns
            cat ${TMPDIR}/kmers_matrix.txt | transpose | awk '!seen[substr($0, index($0, " "))]++' | transpose > ${TMPDIR}/kmers_matrix_dereplicated.txt
            
            # Dereplicate genomes
            while read -r genome; do
                if head -n1 ${TMPDIR}/kmers_matrix_dereplicated.txt | grep -q -w "$genome"; then
                    # Rebuild the absolute path to the genome file
                    realpath -s $(grep "^${genome} " ${TMPDIR}/genomes.fof | cut -d' ' -f3) >> ${TMPDIR}/genomes_dereplicated.txt
                fi
            done <<<"$(head -n1 ${TMPDIR}/kmers_matrix.txt | tr " " "\n")"
            
            # Use the new list of dereplicated genomes
            if [[ -f ${TMPDIR}/genomes_dereplicated.txt ]]; then
                INLIST=${TMPDIR}/genomes_dereplicated.txt
            fi

            # Count how many genomes passed the dereplication
            HOW_MANY=$(cat ${INLIST} | wc -l)
            printf "\t%s genomes passed the dereplication\n" "${HOW_MANY}"
        fi
    else
        # No input genomes survived from the quality control step
        printf "No input genomes available!\n"
        PIPELINE_END_TIME="$(date +%s.%3N)"
        PIPELINE_ELAPSED="$(bc <<< "${PIPELINE_END_TIME}-${PIPELINE_START_TIME}")"
        printf "\nTotal elapsed time: %s\n\n" "$(displaytime ${PIPELINE_ELAPSED})"
        
        # Print credits before stopping the pipeline execution
        credits
        
        exit 0
    fi
fi

# Count how many input genomes survived in case they have been quality controlled and dereplicated
HOW_MANY=$(cat ${INLIST} | wc -l)
if [[ "${HOW_MANY}" -gt "1" ]]; then
    # Create a temporary folder in case input genomes are gzip compressed
    mkdir -p $TMPDIR/genomes

    # Keep track of the lineages that must be rebuilt
    REBUILD=()
    # Keep track of the unassigned genomes
    # They will be assigned to new group
    UNASSIGNED=()
    # Process input genomes
    while read GENOMEPATH; then
        GENOMEEXT="${GENOMEPATH##*.}"
        GENOMENAME="$(basename ${GENOMEPATH%.*})"
        FILEPATH=$GENOMEPATH
        # Decompress input genome in case it is gzip compressed
        if [[ "$GENOMEPATH" = *.gz ]]; then
            GENOMEEXT="${GENOMENAME##*.}"
            GENOMENAME="${GENOMENAME%.*}"
            gunzip -c $GENOMEPATH > $TMPDIR/genomes/${GENOMENAME}.fna
            FILEPATH=$TMPDIR/genomes/${GENOMENAME}.fna
        fi

        printf "\nProfiling %s\n" "$GENOMENAME"
        # Run the profiler to establish the closest genome and the closest group for each taxonomic level in the tree
        . ${SCRIPT_DIR}/profile.sh --input-file=$FILEPATH \
                                   --input-id=$FILEPATH \
                                   --tree=${DBDIR}/k__${KINGDOM}/index/index.detbrief.sbt
                                   --expand \
                                   --output-dir=$TMPDIR/profiling/ \
                                   --output-prefix=$GENOMENAME \
                                   > /dev/null 2>&1 # Silence the profiler
        # Define output file path with profiles
        PROFILE=${TMPDIR}/profiling/${GENOMENAME}__profiles.tsv
        
        if [[ -f $PROFILE ]]; then
            # Discard the genome if the score is 1.0 compared to the closest match at the species level
            # Do not discard the input genome if it is a reference genome and the closest genome in the database
            # is a MAG with a perfect overlap of kmers (score 1.0)
            CLOSEST_GENOME="$(grep "${GENOMENAME}.${GENOMEEXT}" $PROFILE | grep -w "genome" | cut -d$'\t' -f3)"
            CLOSEST_GENOME_SCORE="$(grep "${GENOMENAME}.${GENOMEEXT}" $PROFILE | grep -w "genome" | cut -d$'\t' -f4)"
            # Print closest genome
            printf "\tClosest genome: %s (score: %s)\n" "${CLOSEST_GENOME}" "${CLOSEST_GENOME_SCORE}"
            # Reconstruct the closest taxa
            LEVELS=("kingdom" "phylum" "class" "order" "family" "genus" "species")
            CLOSEST_TAXA=""
            CLOSEST_SCORE=""
            printf "\tClosest lineage:\n"
            for level in ${LEVELS[@]}; do
                CLOSEST_LEVEL="$(grep "${GENOMENAME}.${GENOMEEXT}" $PROFILE | grep -w "$level" | cut -d$'\t' -f3)"
                CLOSEST_LEVEL_SCORE="$(grep "${GENOMENAME}.${GENOMEEXT}" $PROFILE | grep -w "$level" | cut -d$'\t' -f4)"
                CLOSEST_TAXA=${CLOSEST_TAXA}"|"${CLOSEST_LEVEL}
                # Print profiler result
                printf "\t\t%s: %s (score: %s)\n" "${level}" "${CLOSEST_LEVEL}" "${CLOSEST_LEVEL_SCORE}"
                # Keep track of the species score
                if [[ "${CLOSEST_LEVEL}" = s__* ]]; then
                    CLOSEST_SCORE=${CLOSEST_LEVEL_SCORE}
                fi
            done
            # Trim the first pipe out of the closest taxonomic label
            CLOSEST_TAXA=${CLOSEST_TAXA:1}
            # Define taxa path
            CLOSEST_TAXADIR=${DBDIR}/$(echo "${CLOSEST_TAXA}" | sed 's/|/\//g')

            SKIP_GENOME=false
            # Check whether the input genome must be discarded
            if [[ "${CLOSEST_GENOME_SCORE}" -eq "1.0" ]]; then
                if [[ "$TYPE" = "MAGs" ]]; then
                    if [[ -f "${CLOSEST_TAXADIR}/genomes.txt" ]] && grep -q "" ${CLOSEST_TAXADIR}/genomes.txt; then
                        # If the input genome is a MAG and the closest genome is a reference
                        # Discard the input genome
                        ${SKIP_GENOME}=true
                        # Print the reason why we discard the input genome
                        printf "\tDiscarding genome:\n"
                        printf "\t\tInput genome is a MAG and the closest genome is a reference\n"
                    elif [[ -f "${CLOSEST_TAXADIR}/mags.txt" ]] && grep -q "" ${CLOSEST_TAXADIR}/mags.txt; then
                        # If the input genome is a MAG and the closest genome is a MAG
                        # Discard the input genome
                        ${SKIP_GENOME}=true
                        # Print the reason why we discard the input genome
                        printf "\tDiscarding genome:\n"
                        printf "\t\tInput genome is a MAG and the closest genome is a MAG\n"
                    fi
                elif [[ "$TYPE" = "references" ]]; then
                    if [[ -f "${CLOSEST_TAXADIR}/genomes.txt" ]] && grep -q "" ${CLOSEST_TAXADIR}/genomes.txt; then
                        # If the input genome is a reference and the closest genome is a reference
                        # Discard the input genome
                        ${SKIP_GENOME}=true
                        # Print the reason why we discard the input genome
                        printf "\tDiscarding genome:\n"
                        printf "\t\tInput genome is a reference and the closest genome is a reference\n"
                    fi
                fi
            fi

            if ! ${SKIP_GENOME}; then
                # Process MAGs or reference genomes
                if [[ "$TYPE" = "MAGs" ]]; then
                    # Check whether the closest score is enough with respect to the boundaries of the closest lineage
                    # TODO

                    if [[ "${CLOSEST_SCORE}" -ge "" ]]; then # TODO
                        # Assign the current genome to the closest lineage
                        TARGETGENOME=${CLOSEST_TAXADIR}/genomes/${GENOMENAME}.${GENOMEEXT}
                        cp $FILEPATH $TARGETGENOME
                        if [[ ! "$GENOMEEXT" = "gz" ]]; then
                            # Compress input genome
                            gzip ${CLOSEST_TAXADIR}/genomes/${GENOMENAME}.${GENOMEEXT}
                            TARGETGENOME=${CLOSEST_TAXADIR}/genomes/${GENOMENAME}.${GENOMEEXT}.gz
                        fi
                        # Add the current genome to the list of genomes in current taxonomy
                        echo "$GENOMENAME : $TARGETGENOME" >> ${CLOSEST_TAXADIR}/genomes.fof
                        echo "$TARGETGENOME" >> ${CLOSEST_TAXADIR}/mags.txt
                        # Do not remove the index here because there could be other input genomes with the same taxonomic label
                        REBUILD+=(${CLOSEST_TAXA})
                        # Print assignment message
                        printf "\tAssignment:\n"
                        printf "\t\t%s\n\n" "${CLOSEST_TAXA}"
                    else
                        # Mark the genome as unassigned
                        UNASSIGNED+=($GENOMEPATH)
                        # Print unassignment message
                        printf "\tUnassigned\n\n"
                    fi
                elif [[ "$TYPE" = "references" ]]; then
                    # Retrieve the taxonomic label from --taxa input file
                    TAXALABEL="$(grep -w "$GENOMENAME" $TAXA | cut -d$'\t' -f2)"
                    # Define taxonomy folder
                    TAXDIR=${DBDIR}/$(echo "${TAXALABEL}" | sed 's/|/\//g')
                    TARGETGENOME=${TAXDIR}/genomes/${GENOMENAME}.${GENOMEEXT}
                    # Print input genome taxonomic label
                    printf "\tTaxonomic label:\n"
                    printf "\t\t%s\n\n" "$TAXALABEL"

                    if [[ -d $TAXDIR ]]; then
                        # If the taxonomic label of the input genome already exists in the database
                        # add the new genome to the assigned taxonomic branch and rebuild the SBTs
                        cp $FILEPATH $TARGETGENOME
                        if [[ ! "$GENOMEEXT" = "gz" ]]; then
                            # Compress input genome
                            gzip ${TAXDIR}/genomes/${GENOMENAME}.${GENOMEEXT}
                            TARGETGENOME=${TAXDIR}/genomes/${GENOMENAME}.${GENOMEEXT}.gz
                        fi
                        # Add the current genome to the list of genomes in current taxonomy
                        echo "$GENOMENAME : $TARGETGENOME" >> $TAXDIR/genomes.fof
                        echo "$TARGETGENOME" >> $TAXDIR/genomes.txt
                        # Do not remove the index here because there could be other input genomes with the same taxonomic label
                        REBUILD+=($TAXALABEL)
                    else
                        # In case the current taxonomic label does not exist in database
                        # Check whether the closest score is enough with respect to the boundaries of the closest lineage
                        # TODO

                        if [[ "${CLOSEST_SCORE}" -ge "" ]]; then # TODO
                            # Check whether the closest taxonomy contains any reference genomes
                            HOW_MANY_REFERENCES=$(cat ${CLOSEST_TAXADIR}/genomes.txt | wc -l)
                            if [[ "${HOW_MANY_REFERENCES}" -eq "0" ]]; then
                                # If the closest genome belongs to a new cluster with no reference genomes
                                # Assign the current reference genome to the new cluster and rename its lineage with the taxonomic label of the reference genome
                                # TODO
                            elif [[ "${HOW_MANY_REFERENCES}" -ge "1" ]]; then
                                # If the closest genome belong to a cluster with at least a reference genome
                                # If thetaxonomic labels of the current reference genome and that one of the closest genome do not match
                                # Report the inconsistency and assign the current reference genome to the closest cluster
                                # TODO
                            fi
                        else
                            # If nothing is close enough to the current genome and its taxonomic label does not exist in the database
                            # Create a new branch with the new taxonomy for the current genome
                            mkdir -p $TAXDIR/genomes
                            cp $FILEPATH $TARGETGENOME
                            if [[ ! "$GENOMEEXT" = "gz" ]]; then
                                # Compress input genome
                                gzip ${TAXDIR}/genomes/${GENOMENAME}.${GENOMEEXT}
                                TARGETGENOME=${TAXDIR}/genomes/${GENOMENAME}.${GENOMEEXT}.gz
                            fi
                            # Add the current genome to the list of genomes in current taxonomy
                            echo "$GENOMENAME : $TARGETGENOME" >> $TAXDIR/genomes.fof
                            echo "$TARGETGENOME" >> $TAXDIR/genomes.txt
                            # Do not remove the index here because there could be other input genomes with the same taxonomic label
                            REBUILD+=($TAXALABEL)
                        fi
                    fi
                fi
            fi
        fi

        # Remove the uncompressed genome in temporary folder
        if [[ -f $TMPDIR/genomes/${GENOMENAME}.fna ]]; then 
            rm $TMPDIR/genomes/${GENOMENAME}.fna
        fi
    done <$INLIST

    # Cluster unassigned genomes before rebuilding the updated lineages
    if [[ "${#UNASSIGNED[@]}" -gt "0" ]]; then
        # The kmers matrix already exists in case the dereplication step has been enabled
        if [[ ! -f ${TMPDIR}/kmers_matrix.txt ]]; then
            GENOMES_FOF=${TMPDIR}/genomes.fof
            # Unassigned genomes are MAGs only
            for MAGPATH in ${UNASSIGNED[@]}; do
                # Define a genomes.fof file with the unassigned genomes
                GENOME_NAME="$(basename $MAGPATH)"
                echo "${GENOME_NAME} : $MAGPATH" >> ${GENOMES_FOF}
            done

            # Run kmtricks to build the kmers matrix
            kmtricks_matrix_wrapper ${GENOMES_FOF} \
                                    ${TMPDIR}/matrix \
                                    ${NPROC} \
                                    ${TMPDIR}/kmers_matrix.txt
            
            # Add header to the kmers matrix
            HEADER=$(awk 'BEGIN {ORS = " "} {print $1}' ${GENOMES_FOF})
            echo "#kmer $HEADER" > ${TMPDIR}/kmers_matrix_wh.txt
            cat ${TMPDIR}/kmers_matrix.txt >> ${TMPDIR}/kmers_matrix_wh.txt
            mv ${TMPDIR}/kmers_matrix_wh.txt ${TMPDIR}/kmers_matrix.txt
        fi

        # Cluster genomes according to the custom boundaries
        # Define a cluster for each taxomomic level
        # Look at the genomes profiles and update or build new clusters 
        # Add full taxonomy to the REBUILD list
        # Update the genomes.fof and the mags.txt tables
        # TODO
    fi

    # Check whether there is at least one lineage that must be rebuilt
    if [[ "${#REBUILD[@]}" -gt "0" ]]; then
        # Extract taxonomic levels from the list of taxa that must be rebuilt
        # Process all the species first, then all the genera, and so on up to the kingdom
        printf "Updating the database\n"
        for POS in $(seq 7 1); do 
            TAXALIST=()
            for LABEL in ${REBUILD[@]}; do
                LEVELS=($(echo $LABEL | tr "|" " "))
                SUBLEVELS=("${LEVELS[@]:0:$POS}")
                TAXONOMY=$(printf "|%s" "${SUBLEVELS[@]}")
                TAXALIST+=(${TAXONOMY:1})
            done
            # Remove duplicate entries
            TAXALIST=$(printf "%s\0" "${TAXALIST[@]}" | sort -uz | xargs -0 printf "%s ")
            # Rebuild the sequence bloom trees
            for TAXONOMY in ${TAXALIST[@]}; do
                printf "\t%s\n" "$TAXONOMY"
                if [[ -d $TAXONOMY/index ]]; then
                    # Remove the index
                    rm -rf $TAXONOMY/index
                    # Remove the copy of the root node
                    LEVELNAME="${TAXONOMY##*\|}"
                    rm ${TAXONOMY}/${LEVELNAME}.bf
                    if [[ "$POS" -eq "7" ]]; then
                        # In case of species
                        # Rebuild the index with kmtricks
                        kmtricks_index_wrapper ${TAXONOMY}/genomes.fof \
                                         $DBDIR \
                                         ${KMER_LEN} \
                                         ${FILTER_SIZE} \
                                         $NPROC
                    else
                        # In case of all the other taxonomic levels
                        # Rebuild the index with howdesbt
                        howdesbt_wrapper $TAXONOMY ${FILTER_SIZE}
                    fi
                else
                    printf "\t\t[ERROR] No index found!\n"
                fi
            done
        done
    else
        # In case nothing must be rebuilt
        printf "No lineages have been updated!\n"
    fi
else
    # No input genomes survived from the quality control step and dereplication
    printf "No input genomes available!\n"
    PIPELINE_END_TIME="$(date +%s.%3N)"
    PIPELINE_ELAPSED="$(bc <<< "${PIPELINE_END_TIME}-${PIPELINE_START_TIME}")"
    printf "\nTotal elapsed time: %s\n\n" "$(displaytime ${PIPELINE_ELAPSED})"
    
    # Print credits before stopping the pipeline execution
    credits

    exit 0
fi

# Cleanup temporary data
if ${CLEANUP}; then
    # Remove tmp folder
    if [[ -d $TMPDIR ]]; then
        printf "Cleaning up temporary folder:\n"
        printf "\t%s\n" "${TMPDIR}"
        rm -rf ${TMPDIR}
    fi
fi

PIPELINE_END_TIME="$(date +%s.%3N)"
PIPELINE_ELAPSED="$(bc <<< "${PIPELINE_END_TIME}-${PIPELINE_START_TIME}")"
printf "\nTotal elapsed time: %s\n\n" "$(displaytime ${PIPELINE_ELAPSED})"

# Print credits
credits

exit 0