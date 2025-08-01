# Load the necessary library
library(optparse)
source(system.file("sim/sim_func.R", package = "pannagram"))
source(system.file("utils/utils.R", package = "pannagram"))

# Define options
option_list = list(
  make_option(c("--out_dir"), type = "character", default = NULL,
              help = "Path to the output coverage file", metavar = "FILE"),
  make_option(c("--sim"), type = "numeric", default = 90,
              help = "Similarity threshold", metavar = "NUMBER"),
  make_option(c("--coverage"), type = "numeric", default = NULL,
              help = "Coverage threshold", metavar = "NUMBER")
)

# Create the option parser
opt_parser = OptionParser(option_list = option_list)

# Parse the arguments
opt = parse_args(opt_parser)

# Check for the presence of all required arguments
output.dir <- ifelse(!is.null(opt$out_dir), opt$out_dir, 
                      stop("Output file not specified", call. = FALSE))
sim.cutoff <- ifelse(!is.null(opt$sim), opt$sim, 
                     stop("Similarity threshold not specified", call. = FALSE))
sim.cutoff = as.numeric(sim.cutoff)

coverage <- ifelse(is.null(opt$coverage), sim.cutoff, opt$coverage)

# ---- Testing ----

# blast.file = 'tmp.txt.blast.tmp'
# source("pannagram/utils.R")
# fasta.file = 'new_genes/new_genes.fasta'
# sim.cutoff = 0.85


# ---- Main ----

files <- list.files(path = output.dir, pattern = paste0(".*",sim.cutoff,'_', coverage,"\\.cnt$"), full.names = T)
if(length(files) == 0){
  pokazAttention('Query sequences were not found in the genomes; therefore, a copy number table cannot be generated.')
  quit(save = "no", status = 0)
} 
# print(files)

total.cnt.list = list()
total.cnt.names = c()

for (i.file in 1:length(files)) {
  file = files[i.file]
  data <- read.table(file, header = TRUE, stringsAsFactors = F, comment.char = "")
  total.cnt.list[[i.file]] = data[,ncol(data), drop=F]
  total.cnt.names = unique(c(total.cnt.names, rownames(data)))
}

mx.cnt = matrix(0, nrow = length(total.cnt.names), ncol = length(files), 
                dimnames = list(total.cnt.names, NULL))

for (i.file in 1:length(files)) {
  mx.cnt[rownames(total.cnt.list[[i.file]]),i.file] = total.cnt.list[[i.file]][,1]
}


# Colnames
acc.names <- sapply(basename(files), function(s){
  s = strsplit(s, '\\.')[[1]]
  return(s[length(s) - 1])
})

colnames(mx.cnt) = acc.names
# pokaz(acc.names)

write.table(mx.cnt,
            file      = paste0(output.dir, "/_total_cnt_", sim.cutoff, "_", coverage, ".tsv"),
            sep       = "\t",
            quote     = FALSE,
            row.names = TRUE,
            col.names = NA)
