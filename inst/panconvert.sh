#!/bin/bash

set -euo pipefail

show_help() {
    cat << EOF

╔══════════════════════════════════════════════╗
║  P a n n a g r a m   o l d   p r o j e c t   ║
║               c o n v e r t e r              ║
╚══════════════════════════════════════════════╝

This script converts old pannagram projects tree
structure to match newer pannagram version.
Choose to make hardlinks or make copies of files.

Usage: ${0##*/} [OPTIONS]

Mandatory Options:
  --old_project DIR     Original project directory (must exist);
  --new_project DIR     New project directory to create (must not exist);
  --ln | --cp           Operation mode: hardlink or copy files;

Operation Modes:
  --ln                  Create hardlinks of files;
  --cp                  Copy files instead of linking;

Help Options:
  -h, --help            Show this help message and exit

Exactly one of --ln or --cp must be provided.

Examples:
  $ ${0##*/} --old_project pannagram_old/ --new_project pannagram_new/ --ln
  $ ${0##*/} --old_project pannagram_old/ --new_project pannagram_new/ --cp

EOF
}

link_directory_contents() {
    local source_pattern="$1"
    local target_dir="$2"
    local preserve_filenames="${3:-false}"
    local operation="${4}"

    if [[ "$source_pattern" == *"*"* ]]; then
        local base_dir=$(dirname "$source_pattern")
        local pattern=$(basename "$source_pattern")
        
        local matches=()
        while IFS= read -r -d '' item; do
            matches+=("$item")
        done < <(find "$base_dir" -maxdepth 1 -name "$pattern" -print0 2>/dev/null)
        
        if [[ ${#matches[@]} -eq 0 ]]; then
            echo "Warning: No items matched pattern '$source_pattern'" >&2
            return 0
        fi
        
        for item in "${matches[@]}"; do
            if [[ -f "$item" && "$preserve_filenames" == "true" ]]; then
                "$operation" "$item" "$target_dir"/
            elif [[ -d "$item" ]]; then
                local item_name=$(basename "$item")
                local suffix="${item_name#${pattern%\*}}"
                
                if [[ "$preserve_filenames" == "true" ]]; then
                    local specific_target="${target_dir%/}/$item_name"
                else
                    local specific_target="${target_dir%/}/$suffix"
                fi
                
                mkdir -p "$specific_target"
                
                
                find "$item" -mindepth 1 -type d -print0 | while IFS= read -r -d '' subdir; do
                    rel_path="${subdir#$item/}"
                    new_dir="${specific_target}/${rel_path}"
                    mkdir -p "$new_dir"
                done
                
                find "$item" -type f -print0 | while IFS= read -r -d '' file; do
                    rel_path="${file#$item/}"
                    new_file="${specific_target}/${rel_path}"
                    "$operation" "$file" "$new_file"
                done
            elif [[ -f "$item" ]]; then
                local item_name=$(basename "$item")
                local suffix="${item_name#${pattern%\*}}"
                local new_file="${target_dir%/}/$suffix"
                "$operation" "$item" "$new_file"
            else
                echo "Warning: Skipping non-regular file: $item" >&2
            fi
        done
        
    else
        if [[ ! -e "$source_pattern" ]]; then
            echo "Warning: Source '$source_pattern' not found" >&2
            return 0
        fi
        
        if [[ -d "$source_pattern" ]]; then
            echo "Processing directory: $source_pattern to $target_dir"
            
            find "$source_pattern" -mindepth 1 -type d -print0 | while IFS= read -r -d '' dir; do
                rel_path="${dir#$source_pattern/}"
                new_dir="${target_dir}/${rel_path}"
                mkdir -p "$new_dir"
            done
            
            find "$source_pattern" -type f -print0 | while IFS= read -r -d '' file; do
                rel_path="${file#$source_pattern/}"
                new_file="${target_dir}/${rel_path}"
                "$operation" "$file" "$new_file"
            done
        elif [[ -f "$source_pattern" ]]; then
            "$operation" "$source_pattern" "$target_dir"/
        else
            echo "Warning: '$source_pattern' is not a file or directory" >&2
            return 1
        fi
    fi
}

# Initialize flags
link_mode=""
copy_mode=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --old_project)
            old_project="$2"
            shift 2
            ;;
        --new_project)
            new_project="$2/"
            shift 2
            ;;
        --ln)
            if [[ -n "${copy_mode:-}" ]]; then
                echo "Error: --ln and --cp cannot be used together." >&2
                echo "Usage: panconvert --old_project <dir> --new_project <dir> (--ln | --cp)" >&2
                exit 1
            fi
            link_mode=1
            shift
            ;;
        --cp)
            if [[ -n "${link_mode:-}" ]]; then
                echo "Error: --ln and --cp cannot be used together." >&2
                echo "Usage: panconvert --old_project <dir> --new_project <dir> (--ln | --cp)" >&2
                exit 1
            fi
            copy_mode=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            echo "Try '$0 --help' for more information." >&2
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ -z "${old_project:-}" || -z "${new_project:-}" ]]; then
    echo "Usage: panconvert --old_project <dir> --new_project <dir> (--ln | --cp)" >&2
    exit 1
fi

# Check for exactly one operation mode
if [[ (-z "${link_mode:-}" && -z "${copy_mode:-}") || (-n "${link_mode:-}" && -n "${copy_mode:-}") ]]; then
    echo "Error: Exactly one of --ln or --cp must be provided." >&2
    echo "Usage: panconvert --old_project <dir> --new_project <dir> (--ln | --cp)" >&2
    exit 1
fi

# Set operation mode
if [[ -n "${link_mode:-}" ]]; then
    link_or_copy="ln"
else
    link_or_copy="cp"
fi

# Ensure old_project exists
if [[ ! -d "$old_project" ]]; then
    echo "Error: old_project '$old_project' directory does not exist" >&2
    exit 1
fi

# Ensure old_project is of an old pannagram version
if [[ -d "$old_project/.intermediate" ]]; then
    echo "Error: It seems that your project '$old_project' allready has an updated structure" >&2
    echo "Make sure to run ${0##*/} only for old pannagram projects" >&2
    exit 1
fi

# Ensure old_project has a vague structure
if [[ ! -d "$old_project/intermediate" || ! -d "$old_project/plots" ]]; then
    echo "Error: old_project '$old_project' has wrong directory structure" >&2
    echo "Unable to convert." >&2
    exit 1
fi

# Ensure new_project not exist
if [[ -d "$new_project" ]]; then
    echo "Error: new_project directory '$new_project' already exists." >&2
    echo "Remove the directory and run again." >&2
    exit 1
fi

# Check path names
INSTALLED_PATH=$(Rscript -e "cat(system.file(package = 'pannagram'))")
source $INSTALLED_PATH/utils/utils_bash.sh
new_project=$(add_symbol_if_missing "$new_project" "/")
old_project=$(add_symbol_if_missing "$old_project" "/")

# Create directory structure
path_log="${new_project}.logs/"
path_features="${new_project}features/"
path_features_msa="${path_features}msa/"
path_extra="${path_features}extra/"
path_snp="${path_features}snp/"
path_seq="${path_features}seq/"
path_sv="${path_features}sv/"
path_gff="${path_sv}gff/"

path_inter="${new_project}.intermediate/"
path_alignment="${path_inter}alignments/"
path_inter_msa="${path_inter}msa/"
path_blast="${path_inter}blast/"
path_blast_gaps="${path_blast}gaps/"
path_blast_parts="${path_blast}parts/"
path_mafft="${path_inter}mafft/"
path_chrom="${path_inter}chromosomes/"
path_parts="${path_chrom}parts/"
path_parts_mirror="${path_chrom}parts_mirror/"
path_orf="${path_inter}orf/"

path_plots="${new_project}plots/"
path_plots_snp="${path_plots}snp/"
path_plots_sv="${path_plots}sv/"
path_plots_synteny="${path_plots}synteny_pangenome/"
path_plots_pairwise="${path_plots}synteny_pairwise/"

# Create all directories
mkdir -p "$new_project" \
    "$path_log" \
    "$path_features" \
    "$path_features_msa" \
    "$path_extra" \
    "$path_snp" \
    "$path_seq" \
    "$path_sv" \
    "$path_gff" \
    "$path_inter" \
    "$path_alignment" \
    "$path_inter_msa" \
    "$path_blast" \
    "$path_blast_gaps" \
    "$path_blast_parts" \
    "$path_mafft" \
    "$path_chrom" \
    "$path_parts" \
    "$path_parts_mirror" \
    "$path_orf" \
    "$path_plots" \
    "$path_plots_snp" \
    "$path_plots_sv" \
    "$path_plots_synteny" \
    "$path_plots_pairwise"

# link_directory_contents "${old_project}/logs" "$path_log" 
link_directory_contents "${old_project}/plots/plots_*" "$path_plots_pairwise" false "$link_or_copy"

# link_directory_contents "${old_project}/intermediate/alignments_*" "$path_alignment" false "$link_or_copy"
# link_directory_contents "${old_project}/intermediate/blast_gaps_*" "$path_blast_gaps" false "$link_or_copy"
# link_directory_contents "${old_project}/intermediate/blast_parts_*" "$path_blast_parts" false "$link_or_copy"
link_directory_contents "${old_project}/intermediate/chromosomes" "$path_chrom" false "$link_or_copy"
# link_directory_contents "${old_project}/intermediate/parts" "$path_parts" false "$link_or_copy"
# link_directory_contents "${old_project}/intermediate/mafft_*" "$path_mafft" false "$link_or_copy"

link_directory_contents "${old_project}/intermediate/consensus/*.RData" "$path_inter_msa" true "$link_or_copy"
link_directory_contents "${old_project}/intermediate/consensus/*.rds" "$path_inter_msa" true "$link_or_copy"
link_directory_contents "${old_project}/intermediate/consensus/*.h5" "$path_features_msa" true "$link_or_copy"
link_directory_contents "${old_project}/intermediate/consensus/plot_svs" "$path_plots_sv" false "$link_or_copy"
link_directory_contents "${old_project}/intermediate/consensus/plot_synteny" "$path_plots_synteny" false "$link_or_copy"
link_directory_contents "${old_project}/intermediate/consensus/seq" "$path_seq" false "$link_or_copy"
link_directory_contents "${old_project}/intermediate/consensus/snps" "$path_snp" false "$link_or_copy"
link_directory_contents "${old_project}/intermediate/consensus/sv" "$path_sv" false "$link_or_copy"

link_directory_contents "${old_project}/intermediate/*.txt" "$path_inter" false "$link_or_copy"

echo "Directory structure created at: $new_project"