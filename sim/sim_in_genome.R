# Load the necessary library
library(optparse)
source('sim/sim_func.R')
source('utils/utils.R')

# Define options
option_list = list(
  make_option(c("--in_file"), type = "character", default = NULL,
              help = "Path to the fasta file with sequences", metavar = "FILE"),
  make_option(c("--res"), type = "character", default = NULL,
              help = "Path to the BLAST results", metavar = "FILE"),
  make_option(c("--out"), type = "character", default = NULL,
              help = "Path to the output coverage file", metavar = "FILE"),
  make_option(c("--sim"), type = "numeric", default = 90,
              help = "Similarity threshold", metavar = "NUMBER")
)

# Create the option parser
opt_parser = OptionParser(option_list = option_list)

# Parse the arguments
opt = parse_args(opt_parser)

# Check for the presence of all required arguments
fasta.file <- ifelse(!is.null(opt$in_file), opt$in_file, 
                     stop("FASTA file not specified", call. = FALSE))
blast.file <- ifelse(!is.null(opt$res), opt$res, 
                     stop("BLAST file not specified", call. = FALSE))
output.file <- ifelse(!is.null(opt$out), opt$out, 
                      stop("Output file not specified", call. = FALSE))
sim.cutoff <- ifelse(!is.null(opt$sim), opt$sim, 
                     stop("Similarity threshold not specified", call. = FALSE))
sim.cutoff = as.numeric(sim.cutoff) / 100


# ---- Testing ----

# blast.file = 'tmp.txt.blast.tmp'
# source('pannagram/utils.R')
# fasta.file = 'new_genes/new_genes.fasta'
# sim.cutoff = 0.85


# ---- Main ----

# Rename the output file
output.file = paste(output.file, round(sim.cutoff * 100), sep = '_')


v = read.table(blast.file, stringsAsFactors = F)
v = v[v$V6 >= sim.cutoff * 100,]

# seqs = readFastaMy(fasta.file)
# v$len1 = nchar(seqs)[v$V1]
# rm(seqs)
len1 = v$V9
v = v[,1:8,drop=F]
v$len1 = len1

res = findHitsInRef(v, sim.cutoff = sim.cutoff, echo = F)

# Sort V4 and V5 positions
idx.tmp = res$V4 > res$V5
# print(sum(idx.tmp))
# print(sum(res$strand == '-'))

tmp = res$V4[idx.tmp]
res$V4[idx.tmp] = res$V5[idx.tmp]
res$V5[idx.tmp] = tmp

blastres2gff(res, paste(output.file, '.gff', sep = ''))

write.table(res, paste(output.file, '.table', sep = ''), quote = F, row.names = F, col.names = T, sep = '\t')

# Copy-number information
res.cnt =as.data.frame.matrix(table(res$V1, res$V8))
res.cnt$total = rowSums(res.cnt)
res.cnt = res.cnt[order(-res.cnt$total),]
write.table(res.cnt, paste(output.file, '.cnt', sep = ''), quote = F, row.names = T, col.names = T, sep = '\t')

cnt = tapply(res$V8, res$V1, length)
pokaz('Mean, min, max number of hits per sequence:', mean(cnt),  min(cnt),  max(cnt))
pokaz('Number of hits found:', nrow(res))




