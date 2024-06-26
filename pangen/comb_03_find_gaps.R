# Get positiona for an extra alignment

suppressMessages({
  library(foreach)
  library(doParallel)
  library(optparse)
  library(crayon)
  library(rhdf5)
})

source("utils/utils.R")
# source("pangen/synteny_funcs.R")

# pokazStage('Step 9. Find Positions of Common Gaps in the Reference-Free Multiple Genome Alignment')

# ***********************************************************************
# ---- Command line arguments ----

args = commandArgs(trailingOnly=TRUE)

option_list = list(
  make_option(c("--path.cons"), type="character", default=NULL, 
              help="path to consensus directory", metavar="character"),
  make_option(c("-p", "--ref.pref"), type="character", default=NULL, 
              help="prefix of the reference file", metavar="character"),
  make_option(c("-c", "--cores"), type = "integer", default = 1, 
              help = "number of cores to use for parallel processing", metavar = "integer")
); 

opt_parser = OptionParser(option_list=option_list);
opt = parse_args(opt_parser, args = args);

# print(opt)

# ***********************************************************************
# ---- Values of parameters ----

# Set the number of cores for parallel processing
num.cores.max = 10
num.cores <- min(num.cores.max, ifelse(!is.null(opt$cores), opt$cores, num.cores.max))


# Path with the consensus output
if (!is.null(opt$path.cons)) path.cons <- opt$path.cons
if(!dir.exists(path.cons)) stop('Consensus folder doesn’t exist')

# Reference genome
if (is.null(opt$ref.pref)) {
  stop("ref.pref is NULL")
} else {
  ref.pref <- opt$ref.pref
}

# ***********************************************************************
# ---- Combinations of chromosomes query-base to create the alignments ----

# Testing
if(F){
  library(rhdf5)
  path.cons = './'
  ref.pref = '0'
  options("width"=200, digits=10)
}


s.pattern <- paste("^", 'res_', ".*", '_ref_', ref.pref, sep = '')
files <- list.files(path = path.cons, pattern = s.pattern, full.names = FALSE)
pref.combinations = gsub("res_", "", files)
pref.combinations <- sub("_ref.*$", "", pref.combinations)

# pokaz('Reference:', ref.pref)
# pokaz('Combinations', pref.combinations)

# ----  Combine correspondence  ----

gr.accs.e <- "accs/"
gr.accs.b <- "/accs"
gr.break.e = 'break/'
gr.break.b = '/break'
max.len.gap = 20000

gr.blocks = 'blocks/'


# ***********************************************************************
# ---- MAIN program body ----

loop.function <- function(s.comb, echo = T){
  
  file.comb = paste(path.cons, 'res_', s.comb,'_ref_',ref.pref,'.h5', sep = '')
  
  groups = h5ls(file.comb)
  accessions = groups$name[groups$group == gr.accs.b]
  
  # Create group for blocks
  suppressMessages({ h5createGroup(file.comb, gr.blocks) })
  
  idx.break = c()
  for(acc in accessions){
    
    # pokaz('Accession', acc, 'combination', s.comb)
    
    v.init = h5read(file.comb, paste(gr.accs.e, acc, sep = ''))
    v = v.init
    
    
    # ----  Find breaks  ----
    
    # Find blocks of additional breaks
    v = cbind(v, 1:length(v))                       # 2 - in ref-based coordinates
    v = v[v[,1] != 0,]                              # 1 - existing coordinates of accessions
    v = cbind(v, 1:nrow(v))                       # 3 - ranked order in ref-based coordinates
    v = cbind(v, rank(abs(v[,1])) * sign(v[,1]))  # 4 - signed-ranked-order in accessions coordinates 
    
    # Save blocks
    idx.block.tmp = which(abs(diff(v[,4])) != 1)
    idx.block.df = data.frame(beg = v[c(1,idx.block.tmp+1), 2], end = v[c(idx.block.tmp, nrow(v)), 2])
    
    # pokaz('Number of blocks', length(idx.block.beg))
    v.block = rep(0, length(v.init))
    for(i.bl in 1:nrow(idx.block.df)){
      v.block[idx.block.df$beg[i.bl]:idx.block.df$end[i.bl]] = i.bl
    }
    
    suppressMessages({
      h5write(v.block, file.comb, paste(gr.blocks, acc, sep = ''))
    })
    
    # v = v[order(v[,1]),]  # not necessary
    
    # with the absence, but neighbouring
    idx.tmp = which( (abs(diff(v[,4])) == 1) &  # Neighbouring in accession-based order
                       (abs(diff(abs(v[,3])) == 1)) &  # Neighbouring in ref-based order
                       (abs(diff(v[,1])) <= max.len.gap) &  # Filtering by length in accession coordinates
                       (abs(diff(v[,2])) <= max.len.gap) &  # Filtering by length in reference coordinates
                       (abs(diff(v[,1])) > 1))  # NOT neighbouring in accession-specific coordinates
    
    # Fix (beg < end) order
    idx.tmp.acc = data.frame(beg = v[idx.tmp,2], end = v[idx.tmp+1,2], acc = acc)
    idx.ord = which(idx.tmp.acc$beg > idx.tmp.acc$end)
    if(length(idx.ord) > 0){
      tmp = idx.tmp.acc$beg[idx.ord]
      idx.tmp.acc$beg[idx.ord] = idx.tmp.acc$end[idx.ord]
      idx.tmp.acc$end[idx.ord] = tmp
    }
    # idx.tmp.acc = idx.tmp.acc[order(idx.tmp.acc$beg),]  # order ONLY if ordered before
    
    # Remove overlaps
    idx.overlap = which( (idx.tmp.acc$beg[-1] - idx.tmp.acc$end[-nrow(idx.tmp.acc)]) <= 3)
    
    i.cnt = 0
    if(length(idx.overlap) > 0){
      j.ov = 0
      for(i.ov in idx.overlap){
        if(i.ov <= j.ov) next
        j.ov = i.ov + 1
        while(j.ov %in% idx.overlap){
          j.ov = j.ov + 1
        }
        # print(c(i.ov, j.ov))
        i.cnt = i.cnt + 1
        idx.tmp.acc$end[i.ov] = idx.tmp.acc$end[j.ov]
      }
      idx.tmp.acc = idx.tmp.acc[-(idx.overlap+1),]
    }
    
    
    # Save breaks
    idx.break = rbind(idx.break, idx.tmp.acc)
    
    rmSafe(x.corr)
    rmSafe(x)
    rmSafe(v)
    rmSafe(v.init)
    rmSafe(idx.tmp.acc)
    rmSafe(idx.break.acc)
    
  }
  
  file.breaks = paste(path.cons, 'breaks_', s.comb,'_ref_',ref.pref,'.rds', sep = '')
  saveRDS(idx.break, file.breaks)
  
  rmSafe(idx.break)
  
  H5close()
  gc()
}


# ***********************************************************************
# ---- Loop  ----


if(num.cores == 1){
  for(s.comb in pref.combinations){
    loop.function(s.comb)
  }
} else {
  # Set the number of cores for parallel processing
  myCluster <- makeCluster(num.cores, type = "PSOCK") 
  registerDoParallel(myCluster) 
  
  tmp = foreach(s.comb = pref.combinations, .packages=c('rhdf5', 'crayon'))  %dopar% { 
                              loop.function(s.comb)
                            }
  stopCluster(myCluster)
}

warnings()





