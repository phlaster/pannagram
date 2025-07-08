#!/bin/bash

set -euo pipefail

link_directory_contents() {
    local source_pattern="$1"
    local target_dir="$2"
    local preserve_filenames="${3:-false}"
    
    # Check if source_pattern contains wildcards
    if [[ "$source_pattern" == *"*"* ]]; then
        # Extract the base directory from the pattern
        local base_dir=$(dirname "$source_pattern")
        local pattern=$(basename "$source_pattern")
        
        # Find matching items
        local matches=()
        while IFS= read -r -d '' item; do
            matches+=("$item")
        done < <(find "$base_dir" -maxdepth 1 -name "$pattern" -print0 2>/dev/null)
        
        if [[ ${#matches[@]} -eq 0 ]]; then
            echo "Warning: No items matched pattern '$source_pattern'" >&2
            return 0
        fi
        
        # Process each matched item
        for item in "${matches[@]}"; do
            if [[ -f "$item" && "$preserve_filenames" == "true" ]]; then
                # File with preserve_filenames=true: link directly to target
                echo "Linking file: $item to $target_dir/"
                ln "$item" "$target_dir"/
            elif [[ -d "$item" ]]; then
                # Directory: handle with or without preserve_filenames
                local item_name=$(basename "$item")
                local suffix="${item_name#${pattern%\*}}"
                
                if [[ "$preserve_filenames" == "true" ]]; then
                    # Preserve directory name
                    local specific_target="${target_dir%/}/$item_name"
                else
                    # Use suffix for directory name
                    local specific_target="${target_dir%/}/$suffix"
                fi
                
                mkdir -p "$specific_target"
                
                # Now process this directory
                echo "Processing directory: $item to $specific_target"
                
                # Create all subdirectories
                find "$item" -mindepth 1 -type d -print0 | while IFS= read -r -d '' subdir; do
                    rel_path="${subdir#$item/}"
                    new_dir="${specific_target}/${rel_path}"
                    mkdir -p "$new_dir"
                done
                
                # Create hard links for all files
                find "$item" -type f -print0 | while IFS= read -r -d '' file; do
                    rel_path="${file#$item/}"
                    new_file="${specific_target}/${rel_path}"
                    ln "$file" "$new_file"
                done
            elif [[ -f "$item" ]]; then
                # File without preserve_filenames=true - use default suffix behavior
                local item_name=$(basename "$item")
                local suffix="${item_name#${pattern%\*}}"
                local new_file="${target_dir%/}/$suffix"
                echo "Linking file: $item to $new_file"
                ln "$item" "$new_file"
            else
                echo "Warning: Skipping non-regular file: $item" >&2
            fi
        done
        
    else
        # Non-wildcard version
        if [[ ! -e "$source_pattern" ]]; then
            echo "Warning: Source '$source_pattern' not found" >&2
            return 0
        fi
        
        if [[ -d "$source_pattern" ]]; then
            # Directory
            echo "Processing directory: $source_pattern to $target_dir"
            
            # Create all subdirectories
            find "$source_pattern" -mindepth 1 -type d -print0 | while IFS= read -r -d '' dir; do
                rel_path="${dir#$source_pattern/}"
                new_dir="${target_dir}/${rel_path}"
                mkdir -p "$new_dir"
            done
            
            # Create hard links for all files
            find "$source_pattern" -type f -print0 | while IFS= read -r -d '' file; do
                rel_path="${file#$source_pattern/}"
                new_file="${target_dir}/${rel_path}"
                ln "$file" "$new_file"
            done
        elif [[ -f "$source_pattern" ]]; then
            # Single file
            echo "Linking file: $source_pattern to $target_dir/"
            ln "$source_pattern" "$target_dir"/
        else
            echo "Warning: '$source_pattern' is not a file or directory" >&2
            return 1
        fi
    fi
}

batch_rename() {
    local target_dir="$1"
    local regex="$2"
    
    if [[ ! -d "$target_dir" ]]; then
        echo "Error: Target directory '$target_dir' does not exist" >&2
        return 1
    fi
    
    # Process directories depth-first to handle nested renames
    find "$target_dir" -depth -type d -print0 | while IFS= read -r -d '' dir; do
        # Get the base name of the directory
        dir_basename=$(basename "$dir")
        
        # Apply regex substitution
        new_name=$(sed -r "$regex" <<< "$dir_basename")
        
        # Only rename if the name changed
        if [[ "$dir_basename" != "$new_name" ]]; then
            # Get the parent directory
            parent_dir=$(dirname "$dir")
            new_path="${parent_dir}/${new_name}"
            
            # Skip if the new name is empty
            if [[ -z "$new_name" ]]; then
                echo "Warning: Regex would result in empty name for '$dir'" >&2
                continue
            fi
            
            # Check for conflicts
            if [[ -e "$new_path" ]]; then
                echo "Warning: Cannot rename '$dir' to '$new_path' - path already exists" >&2
                continue
            fi
            
            # Perform the actual rename
            mv -v -- "$dir" "$new_path"
        fi
    done
}

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
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ -z "${old_project:-}" || -z "${new_project:-}" ]]; then
    echo "Usage: $0 --old_project <dir 1> --new_project <dir 2>" >&2
    exit 1
fi

# Ensure old_project exists
if [[ ! -d "$old_project" ]]; then
    echo "Error: old_project '$old_project' directory does not exist" >&2
    exit 1
fi

# Ensure old_project has a vague structure
if [[ ! -d "$old_project/intermediate" || ! -d "$old_project/logs" || ! -d "$old_project/plots" ]]; then
    echo "Error: old_project '$old_project' has wrong directory structure" >&2
    exit 1
fi

# Ensure new_project not exist
if [[ -d "$new_project" ]]; then
    echo "Error: new_project directory '$new_project' already exist" >&2
    exit 1
fi

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

link_directory_contents "${old_project}/logs" "$path_log" 
link_directory_contents "${old_project}/plots/plots_*" "$path_plots_pairwise"

link_directory_contents "${old_project}/intermediate/alignments_*" "$path_alignment"
link_directory_contents "${old_project}/intermediate/blast_gaps_*" "$path_blast_gaps"
link_directory_contents "${old_project}/intermediate/blast_parts_*" "$path_blast_parts"
link_directory_contents "${old_project}/intermediate/chromosomes" "$path_chrom"
link_directory_contents "${old_project}/intermediate/parts" "$path_parts"
link_directory_contents "${old_project}/intermediate/mafft_*" "$path_mafft"

link_directory_contents "${old_project}/intermediate/consensus/*.RData" "$path_inter_msa" true
link_directory_contents "${old_project}/intermediate/consensus/*.rds" "$path_inter_msa" true
link_directory_contents "${old_project}/intermediate/consensus/*.h5" "$path_features_msa" true
link_directory_contents "${old_project}/intermediate/consensus/plot_svs" "$path_plots_sv"
link_directory_contents "${old_project}/intermediate/consensus/plot_synteny" "$path_plots_synteny"
link_directory_contents "${old_project}/intermediate/consensus/seq" "$path_seq"
link_directory_contents "${old_project}/intermediate/consensus/snps" "$path_snp"
link_directory_contents "${old_project}/intermediate/consensus/sv" "$path_sv"

link_directory_contents "${old_project}/intermediate/*.txt" "$path_inter"
# batch_rename "$path_plots_pairwise" 's/^plots_//'

echo "Directory structure created at: $new_project"