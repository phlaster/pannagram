# Modifier of tblastn results to be correctly processed

# Libs
library(optparse)

# Define the command-line options
option_list <- list(
  make_option(c("--file.init"), type = "character", default = NULL, help = "Path to initial BLAST result file"),
  make_option(c("--file.mod"),  type = "character", default = NULL, help = "Path to modified BLAST result file")
)

# Create parser
parser <- OptionParser(option_list = option_list)
args <- parse_args(parser)

file.init <- args$file.init
file.mod <- args$file.mod

# Check that both required arguments are provided
if (is.null(file.init) || is.null(file.mod)) {
  print_help(parser)
  stop("Error: Both --file.init and --file.mod must be provided.")
}

if (file.init == file.mod) {
  stop("Error: --file.init and --file.mod must be different.")
}

if (!file.exists(file.init)) {
  stop("Error: --file.init does not exist.")
}

if (file.exists(file.mod)) {
  stop("Error: --file.mod already exists. Please provide a new file path.")
}

# Print paths for confirmation
res = read.table(file.init, stringsAsFactors = F)

# Modify:
# V2 = query start
# V3 = query end
# V7 = alignment length
# V9 = query length

res$V2 <- (res$V2 - 1) * 3 + 1
res$V3 <- res$V3 * 3
res$V7 <- res$V7 * 3
res$V9 <- res$V9 * 3

write.table(res, file.mod, quote = F, row.names = F, col.names = F, sep = '\t')





