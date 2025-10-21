#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Verify we're in the right environment
if [ -z "$CONDA_PREFIX" ]; then
  echo "Error: Conda environment not activated. Run 'micromamba activate pannagram' first."
  exit 1
fi

# Verify R is in the Conda environment
R_PATH=$(which R)
if [[ "$R_PATH" != "$CONDA_PREFIX/bin/R" ]]; then
  echo "Error: R interpreter is not from the Conda environment ($R_PATH)"
  exit 1
fi

# Display environment information
echo "=== Environment verification ==="
echo "OS: $OSTYPE"
echo "Architecture: $(uname -m)"
echo "CONDA_PREFIX: $CONDA_PREFIX"
which R
R --version | head -n 1

# Install the package
./user.sh

# Set up common variables
ROOT_DIR=$(pwd)
PATH_DATA="$ROOT_DIR/_test_data"
PATH_TOOLS="$ROOT_DIR/_test_tools"

# Determine number of cores based on platform
if [ "$(uname)" = "Linux" ]; then
  CORES=2
else
  CORES=1
fi

# Prepare test data
mkdir -p "$PATH_DATA" "$PATH_TOOLS"
echo -e "GCA_000005845.2\nGCA_000008865.2\nGCA_042189615.1" > "$PATH_DATA/ecoli.txt"
echo -e "GCA_042016495.1\nGCA_042017145.1\nGCA_042017895.1" >> "$PATH_DATA/ecoli.txt"

# Download test data
cd "$PATH_TOOLS"
git clone https://github.com/iganna/poputils.git
cd poputils/genomes

# Apply macOS compatibility patches if needed
if [ "$(uname)" = "Darwin" ]; then
  echo "Running on macOS - applying compatibility patches..."
  sed -i '' 's|/proc/cpuinfo|/dev/null|g' genbank_download_list.sh
fi

# Download genome files
./genbank_download_list.sh -f "$PATH_DATA/ecoli.txt" -p "$PATH_DATA"

# Run the pannagram test
pannagram -pre \
  -path_in _test_data/ \
  -path_out _test_output \
  -ref GCA_000005845.2 \
  -cores $CORES

echo "All tests completed successfully!"