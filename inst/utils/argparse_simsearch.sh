# ----------------------------------------------------------------------------
#            PARAMETERS
# ----------------------------------------------------------------------------

# Function to check if a file has a specific extension
has_extension() {
    local filename="$1"
    shift
    local extensions=("$@")
    local ext="${filename##*.}"

    for allowed_ext in "${extensions[@]}"; do
        if [[ "$ext" == "$allowed_ext" ]]; then
            return 0
        fi
    done
    return 1
}

validate_fasta_suffix() {
    local file="$1"
    local expected_type="$2"

    if [ ! -f "$file" ]; then
        pokaz_error "Error: FASTA file not found: $file"
        return 1
    fi

    if [[ "$expected_type" == "FASTA with protein sequences" ]] && ! has_extension "$file" "${FASTA_PROT_EXT[@]}"; then
        pokaz_error "Error: $expected_type was expected for '$file'. Acceptable suffixes are: ${FASTA_PROT_EXT[*]}"
        return 1
    elif [[ "$expected_type" == "FASTA with nucleotide sequences" ]] && ! has_extension "$file" "${FASTA_NUCL_EXT[@]}"; then
        pokaz_error "Error: $expected_type was expected for '$file'. Acceptable suffixes are: ${FASTA_NUCL_EXT[*]}"
        return 1
    fi

    return 0
}

if [ $# -eq 0 ]; then
    pokaz_error "No arguments provided!"
    help_in_box
    exit 0
fi

if command -v nproc &>/dev/null; then
    max_cores=$(nproc)
else
    max_cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
fi

after_blast_flag=0
keep_blast_flag=0
use_strand=T
use_aa=0
cores=1

# Read arguments
while [ "$1" != "" ]; do
    case $1 in
        -h | --help ) show_help; exit ;;
        -in_seq )    file_input=$2; shift 2 ;;
        -out )       output_pref=$2; shift 2 ;;
        -sim )       sim_threshold=$2; shift 2 ;;
        -cov )       coverage=$2; shift 2 ;;

        -on_seq )    file_seq=$2; shift 2 ;;
        -on_genome ) file_genome=$2; shift 2 ;;
        -on_path )   path_genome=$2; shift 2 ;;

        -afterblast ) after_blast_flag=1; shift ;;
        -keepblast )  keep_blast_flag=1; shift ;;
        -aa )         use_aa=1; shift ;;

        -strandfree ) use_strand=F; shift ;;

        -cores)
        if [[ -n "${2-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
            cores="$2"
            shift 2
        else
            pokaz_error "Error: -cores requires a positive integer."
            exit 1
        fi
        ;;

        * ) pokaz_error "Unknown parameter: $1"; help_in_box; exit 1;;
    esac
done

if (( cores < 1 )); then
  cores=1
elif (( cores > max_cores )); then
  cores=$max_cores
fi
pokaz_message "Running BLAST on ${cores} threads."

# Ensure only one of -on_seq, -on_genome, -on_path is set
count=0
[ ! -z "$file_seq" ] && count=$((count + 1))
[ ! -z "$file_genome" ] && count=$((count + 1))
[ ! -z "$path_genome" ] && count=$((count + 1))

if [ $count -ne 1 ]; then
    pokaz_error "Error: You must specify exactly one of -on_seq, -on_genome, or -on_path."
    help_in_box
    exit 1
fi

# Check if FASTA file parameter is provided
if [ -z "$file_input" ]; then
    pokaz_error "Error: FASTA file not specified"
    help_in_box
    exit 1
fi

# Check if the FASTA file exists
if [ ! -f "$file_input" ]; then
    pokaz_error "Error: Input FASTA file not found: $file_input"
    exit 1
fi

# Check if output file parameter is provided
if [ -z "$output_pref" ]; then
    pokaz_error "Error: Output file not specified"
    help_in_box
    exit 1
fi

# Validate -in_seq
if [ -n "$file_input" ]; then
    if [ "$use_aa" -eq 1 ]; then
        expected_type="FASTA with protein sequences"
    else
        expected_type="FASTA with nucleotide sequences"
    fi

    if ! validate_fasta_suffix "$file_input" "$expected_type"; then
        exit 1
    fi
fi

# Validate -on_seq if set
if [ -n "$file_seq" ]; then
    if ! validate_fasta_suffix "$file_seq" "FASTA with nucleotide sequences"; then
        exit 1
    fi
fi

# Validate -on_genome if set
if [ -n "$file_genome" ]; then
    if ! validate_fasta_suffix "$file_genome" "FASTA with nucleotide sequences"; then
        exit 1
    fi
fi

# Validate -on_path if set
if [ -n "$path_genome" ]; then
    if [ ! -d "$path_genome" ]; then
        pokaz_error "Error: Path genome directory does not exist: $path_genome"
        exit 1
    fi

    for genome_file in "$path_genome"/*; do
        if [ -f "$genome_file" ]; then
            if ! validate_fasta_suffix "$genome_file" "FASTA with nucleotide sequences"; then
                exit 1
            fi
        fi
    done
fi

# Check if similarity threshold parameter is provided
if [ -z "$sim_threshold" ]; then
    if [ "$use_aa" -eq 1 ]; then
        sim_threshold=60
        pokaz_message "Similarity threshold not specified, default for '-aa': ${sim_threshold}"
    else
        sim_threshold=85
        pokaz_message "Similarity threshold not specified, default: ${sim_threshold}"
    fi
fi

# Check if coverage parameter is provided. If not - set qeual to sim
if [ -z "$coverage" ]; then
    coverage=${sim_threshold}
    pokaz_message "Coverage not specified, set to default: ${sim_threshold}"
fi

# Determine BLAST command and database type
if [ "$use_aa" -eq 1 ]; then
    pokaz_message "Searching for proteins in nucleotide db"
    blast_cmd="tblastn"
    dbtype="nucl"
else
    pokaz_message "Searching for nucleotides in nucleotide db"
    blast_cmd="blastn"
    dbtype="nucl"
fi