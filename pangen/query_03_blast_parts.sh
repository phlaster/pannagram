# ----------------------------------------------------------------------------
#            ERROR HANDLING BLOCK
# ----------------------------------------------------------------------------

# Exit immediately if any command returns a non-zero status
set -e

# Keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG

# Define a trap for the EXIT signal
trap 'catch $?' EXIT

# Function to handle the exit signal
catch() {
    # Check if the exit code is non-zero
    if [ $1 -ne 0 ]; then
        echo "\"${last_command}\" command failed with exit code $1."
    fi
}

# ----------------------------------------------------------------------------
#             FUNCTIONS
# ----------------------------------------------------------------------------

source utils/utils_bash.sh

print_usage() {
  echo "-path_ref"
  echo "-path_parts"
  echo "-path_result"
  echo "-ref_pref"
  echo "-all_vs_all"
  echo "-p_ident"
  echo "-cores"
  echo "-penalty"
  echo "-gapopen"
  echo "-gapextend"
  echo "-max_hsps"
}


# ----------------------------------------------------------------------------
#                 PARAMETERS
# ----------------------------------------------------------------------------

while [ $# -gt 0 ]
do
    case $1 in
    # for options with required arguments, an additional shift is required
    -path_ref) path_ref=$2; shift ;;
    -path_parts) parts=$2; shift ;;
    -path_result) blastres=$2; shift ;;
    -ref_pref) ref_pref=$2; shift ;;
    -all_vs_all) all_vs_all=$2; shift ;;
    -p_ident) p_ident=$2; shift ;;
    -cores) cores=$2; shift ;;
    -penalty) penalty=$2; shift ;;
    -gapopen) gapopen=$2; shift ;;
    -gapextend) gapextend=$2; shift ;;
    -max_hsps) max_hsps=$2; shift ;;
    *) print_usage
       echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
    esac
    shift
done

# ----------------------------------------------------------------------------
#                 MAIN
# ----------------------------------------------------------------------------

# pokaz_stage "Step 3. BLAST of parts against the reference genome"
pokaz_message "NOTE: if this stage takes relatively long, use -filter_rep -s 2 to mask highly repetative regions"

# -penalty -2 -gapopen 10 -gapextend 2 -max_hsps 5

penalty="${penalty:--2}"
gapopen="${gapopen:-10}"
gapextend="${gapextend:-2}"
max_hsps="${max_hsps:-1}"
cores="${cores:-30}"


#echo $blastres
mkdir -p $blastres

# echo "Identity ${p_ident}"


# BLAST-search function
run_blast() {
    part_file=$1
    ref_file=$2
    blastres=$3
    p_ident=$4
    penalty=$5
    gapopen=$6
    gapextend=$7
    max_hsps=$8
    all_vs_all=$9

    p_filename=$(basename "$part_file" .fasta)
    p_prefix=${p_filename%_*}
    part_chr=${p_filename##*chr}

    r_filename=$(basename "$ref_file" .fasta)
    r_prefix=${r_filename%_*}
    ref_chr=${r_filename##*chr}


    if [[ "$p_prefix" == "$r_prefix" ]] || { [[ "$part_chr" != "$ref_chr" ]] && [[ ${all_vs_all} == "F" ]]; } || [[ -f "$outfile" ]]; then
        return
    fi

    # echo "${part_chr} ${ref_chr}"

  	p_filename=$(echo "$p_filename" | sed 's/_chr\(.*\)$/_\1/')
    outfile=${blastres}${p_filename}_${ref_chr}.txt

  	# echo ${outfile}

    # blastn -db ${ref_file} -query ${part_file} -out ${outfile} \
    #        -outfmt "7 qseqid qstart qend sstart send pident length qseq sseq sseqid" \
    #        -perc_identity ${p_ident} -penalty $penalty -gapopen $gapopen -gapextend $gapextend -max_hsps $max_hsps \
    #        -word_size 50 > /dev/null 2>> log_err.txt 

    blastn -db ${ref_file} -query ${part_file} -out ${outfile} \
           -outfmt "7 qseqid qstart qend sstart send pident length qseq sseq sseqid" \
           -perc_identity ${p_ident} -penalty $penalty -gapopen $gapopen -gapextend $gapextend \
           -max_hsps $max_hsps  #-word_size 50 

}

export -f run_blast

# Run the parallel

pokaz_message "Reference genome ${ref_pref}"


parallel -j $cores run_blast ::: ${parts}*.fasta ::: $path_ref${ref_pref}_chr*.fasta ::: $blastres ::: $p_ident ::: $penalty ::: $gapopen ::: $gapextend ::: $max_hsps ::: $all_vs_all

# for part in ${parts}*.fasta; do
#   for ref in ${path_ref}${ref_pref}_chr*.fasta; do
#     run_blast "$part" "$ref" "$blastres" "$p_ident" "$penalty" "$gapopen" "$gapextend" "$max_hsps" "$all_vs_all"
#   done
# done



# pokaz_message "Done!"
