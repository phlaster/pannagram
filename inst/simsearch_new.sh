#!/bin/bash

INSTALLED_PATH=$(Rscript -e "cat(system.file(package = 'pannagram'))")

echo $INSTALLED_PATH

source "$INSTALLED_PATH/utils/chunk_error_control.sh"
source "$INSTALLED_PATH/utils/utils_bash.sh"
source "$INSTALLED_PATH/utils/help_simsearch.sh"
source "$INSTALLED_PATH/utils/argparse_simsearch.sh"

# ----------------------------------------------------------------------------
#            MAIN
# ----------------------------------------------------------------------------

# Fix the output file result
output_pref=$(add_symbol_if_missing "$output_pref" "/")
if [ ! -d "${output_pref}" ]; then
    mkdir -p "${output_pref}"
fi
output_pref="${output_pref}simsearch"
pokaz_message "Prefex for the output file was changed to ${output_pref}"

# ---------------------------------------------
# Files for the blast

# Add all FASTA files from path_genome to db_files if path_genome is not empty
if [ ! -z "$path_genome" ]; then

    path_genome=$(add_symbol_if_missing "$path_genome" "/")
    db_files=()

    fasta_extensions=("fa" "fasta" "fna" "fas" "ffn" "frn")

    for ext in "${fasta_extensions[@]}"; do
        for genome_file in "$path_genome"/*.$ext; do
            if [ -e "$genome_file" ]; then
                db_file=$(basename "$genome_file")
                db_files+=("$db_file")
            fi
        done
    done

fi

# Add file_seq to db_files if it's not empty
if [ ! -z "$file_seq" ]; then
    path_genome="$(dirname "$file_seq")/"
    db_files=("$(basename "$file_seq")")
fi

# Add file_genome to db_files if it's not empty
if [ ! -z "$file_genome" ]; then
    path_genome="$(dirname "$file_genome")/"
    db_files=("$(basename "$file_genome")")
fi

# ---------------------------------------------
# Run the pipeline

BLAST_DB_DIR="${output_pref}blastdb"
mkdir -p "$BLAST_DB_DIR"


for db_file in "${db_files[@]}"; do
    base_name=$(basename -- "$db_file")
    base_name_no_ext="${base_name%.*}"  # Remove last extension
    file_out_cnt="${output_pref}.${base_name_no_ext}_${sim_threshold}_${coverage}.cnt"
    
    # Skip processing if count file exists
    if [ -f "$file_out_cnt" ]; then
        echo "Counts for ${base_name_no_ext} already exist."
        continue
    fi

    # Handle after_blast_flag separately - uses existing BLAST results
    if [ "$after_blast_flag" -eq 1 ]; then
        blast_res="${output_pref}.${base_name_no_ext}.blast.tmp"
        if [ ! -f "${blast_res}" ]; then
            pokaz_error "BLAST results file not found: ${blast_res}"
            exit 1
        fi
    else
        # ---------------------------------------------
        # Create BLAST database in OUTPUT directory
        db_output_path="${BLAST_DB_DIR}/${base_name_no_ext}"
        db_file_full="${path_genome}${db_file}"
        
        # Create database if missing
        if [ ! -f "${db_output_path}.nhr" ]; then
            pokaz_stage "Creating BLAST database in output directory for $db_file..."
            makeblastdb -in "$db_file_full" -dbtype nucl -out "$db_output_path" > /dev/null
        fi

        # ---------------------------------------------
        # Run BLAST
        blast_res="${output_pref}.${base_name_no_ext}.blast.tmp"
        pokaz_stage "BLAST search in ${base_name_no_ext}..."
        blastn \
            -db "$db_output_path" \
            -query "$file_input" \
            -out "$blast_res" \
            -outfmt "6 qseqid qstart qend sstart send pident length sseqid qlen slen" \
            -perc_identity "$((sim_threshold - 1))"
    fi

    # Check if the BLAST results file is empty
    if [ ! -s "${blast_res}" ]; then
        pokaz_message "Blast result is empty for ${db_file}"
        continue
    fi

    # ---------------------------------------------
    # Proceed to similarity search
    pokaz_stage "Search in ${db_file}: similarity ${sim_threshold}, coverage ${coverage}..."

    # Determine if the search is on a set of sequences or a genome
    if [ -n "$file_seq" ]; then
        # On a set of sequences
        Rscript "$INSTALLED_PATH/sim/sim_in_seqs.R" \
            --in_file "$file_input" \
            --res "$blast_res" \
            --out "${output_pref}.${db_name}.rds" \
            --sim "$sim_threshold" \
            --use_strand "$use_strand" \
            --db_file "$db_file_full" \
            --coverage "${coverage}"
    else
        # On a genome
        Rscript "$INSTALLED_PATH/sim/sim_in_genome.R" \
            --in_file "$file_input" \
            --res "$blast_res" \
            --out "${output_pref}.${db_name}" \
            --sim "$sim_threshold" \
            --coverage "$coverage"
    fi

    # Remove the BLAST temporary file if not needed
    if [ "$keep_blast_flag" -ne 1 ] && [ "$after_blast_flag" -ne 1 ]; then
        rm "$blast_res"
    fi

done

# Combine all files to the total count file
if [[ -z "$file_seq" && -z "$file_genome" ]]; then
    Rscript "$INSTALLED_PATH/sim/sim_in_genome_combine.R" \
        --out "$output_pref" \
        --sim "$sim_threshold" \
        --coverage "$coverage"
fi

pokaz_message "Done!"