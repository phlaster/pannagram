# All function to find similarities

#' Find Hits in Reference
#'
#' This function identifies hits in a reference sequence based on similarity cutoffs and strand orientation. 
#' It handles exact matches and fragmented matches.
#'
#' @param v A data frame blast result data. 
#' The structure of 'v' must include the following NON-factor columns:
#'   - V1: Identifier for genomic elements or fragments.
#'   - V2 and V3: Genomic coordinates (start and end positions of a gene or fragment).
#'   - V4 and V5: Coordinate-related columns, representing positions in a reference sequence.
#'   - V6: Numerical value associated with each genomic element, used for averaging.
#'   - V7: Similarity measure.
#'   - V8: Another identifier of the reference sequence.
#'   - len1: Column representing length of queries, crucial for certain calculations in the function.

#' @param sim.cutoff The similarity cutoff for considering a hit. Defaults to 0.9.
#' @param echo Logical flag to indicate if intermediate steps should be printed. Defaults to TRUE.
#'
#' @return A data frame with hits that meet the specified similarity criteria. The result includes additional information like strand orientation and coverage details.
#'
#' @examples
#' 
#' # First, generate the required data structure using the BLAST command:
#' # blastn -db db.fasta -query query.fasta -out out.txt -outfmt "7 qseqid qstart qend sstart send pident length sseqid"
#' # Then, read the output into a data frame:
#' v <- read.table('out.txt', stringsAsFactors = FALSE)
#' 
#' # Next, add an additional column 'len1' to 'v', which represents the length of sequences or genomic features.
#' # This can be done based on your specific data and requirements. For example:
#' # v$len1 <- calculateLengths(v) # Replace 'calculateLengths' with actual calculation or data extraction
#' 
#' # Finally, use the function with the prepared data frame:
#' result <- findHitsInRef(v, sim.cutoff = 0.9, echo = TRUE)
#' 
findHitsInRef <- function(v, sim.cutoff, coverage=NULL, echo = T){
  
  
  if(is.null(coverage)) coverage = sim.cutoff
  if(!('len1' %in% colnames(v))) stop('No column len1 in the data.frame')
  
  if (! ((sim.cutoff >= 0) & (sim.cutoff <= 1))) {
    stop(paste("Similarity cutoff should be between 0 and 1, now", sim.cutoff))
  }
  
  if (! ((coverage >= 0) & (coverage <= 1))) {
    stop(paste("Coverage cutoff should be between 0 and 1, now", coverage))
  }
  
  s.tmp.comb = '___'
  
  # ---- Exact match ----
  # Take to the analysis those positions, which are already enough under the coverage threshold
  idx.include = (v$V7 / v$len1 > coverage)  # CHANGED FROM sim.cutoff
  v.include = v[idx.include,]
  v.include$V7 = v.include$V3 - v.include$V2 + 1
  
  # Result variable
  v.sim = v.include
  
  # Add Strand
  s.strand = c('+', '-')
  v.sim$strand = s.strand[(v.sim$V4 > v.sim$V5) * 1 + 1]
  
  # ---- Fragmented match ----
  # Decide what to do with those, which are covered by pieces
  idx.non.include = !idx.include
  
  if(sum(idx.non.include) == 0){
    return(v.sim)
  }
  
  if(echo) pokaz('Work with partial genes')
  idx.strand = (v$V4 > v$V5) * 1
  for(i.strand in 0:1){
    if(echo) pokaz(paste('Strand', i.strand))
    v.rest = v[(idx.non.include) & (idx.strand == i.strand),]
    
    if(nrow(v.rest) == 0) next
    
    if(i.strand == 1){
      # tmp = v.rest$V4
      # v.rest$V4 = v.rest$V5
      # v.rest$V5 = tmp
      
      tmp.max = max(c(v.rest$V4, v.rest$V5)) + 1
      v.rest[,c('V4', 'V5')] = tmp.max - v.rest[,c('V4', 'V5')]
    }
    
    # if only one record - delete
    v.rest = v.rest[order(v.rest$V8),]
    v.rest = v.rest[order(v.rest$V1),]
    n.rest = nrow(v.rest)
    idx.one = which((v.rest$V8[-1] == v.rest$V8[-n.rest]) & (v.rest$V1[-1] == v.rest$V1[-n.rest]))
    if(length(idx.one) == 0) next # If nothing is left
    
    idx.one = sort(unique(c(idx.one,idx.one+1)))
    v.rest = v.rest[idx.one,,drop=F]
    
    if(nrow(v.rest) == 0) next
    
    v.rest = v.rest[order(-v.rest$V5),]
    v.rest = v.rest[order(v.rest$V4),]
    v.rest = v.rest[order(v.rest$V8),]
    v.rest = v.rest[order(v.rest$V1),]
    # remove nestedness
    idx.nested = 1
    while(length(idx.nested) > 0){
      idx.nested = which((v.rest$V2[-1] >= v.rest$V2[-nrow(v.rest)]) & 
                           (v.rest$V3[-1] <=v.rest$V3[-nrow(v.rest)]) & 
                           (v.rest$V4[-1] >= v.rest$V4[-nrow(v.rest)]) & 
                           (v.rest$V5[-1] <=v.rest$V5[-nrow(v.rest)]) & 
                           (v.rest$V1[-1] == v.rest$V1[-nrow(v.rest)]) &
                           (v.rest$V8[-1] == v.rest$V8[-nrow(v.rest)])) + 1
      # print(length(idx.nested))
      if(length(idx.nested) == 0) next
      v.rest = v.rest[-idx.nested,]  
    }
    
    v.rest$cover = v.rest$V3 - v.rest$V2 + 1
    v.rest$ref.overlap1 = c(v.rest$V4[-1] - v.rest$V5[-nrow(v.rest)] - 1, 0)
    v.rest$allowedoverlap1 = v.rest$len1 * (1-coverage)  # CHANGED FROM sim.cutoff
    suffixname = (v.rest$ref.overlap1 > v.rest$allowedoverlap1) * 1
    v.rest$suffixname = c(1, suffixname[-length(suffixname)])
    v.rest$suffixname[1 + which(v.rest$V8[-1] != v.rest$V8[-nrow(v.rest)])] = 1
    v.rest$suffixname[1 + which(v.rest$V3[-1] < v.rest$V2[-nrow(v.rest)])] = 1
    
    v.rest$suffixname[1 + which((v.rest$V2[-1] < v.rest$V2[-nrow(v.rest)]) &
                                  (v.rest$V3[-1] < v.rest$V3[-nrow(v.rest)]))] = 1
    
    v.rest$suffixname = cumsum(v.rest$suffixname)
    v.rest$V8 = paste(v.rest$V8, v.rest$suffixname, sep = '|id')
    
    # if only one record - delete
    v.rest = v.rest[order(v.rest$V8),]
    v.rest = v.rest[order(v.rest$V1),]
    n.rest = nrow(v.rest)
    idx.one = which((v.rest$V8[-1] == v.rest$V8[-n.rest]) & (v.rest$V1[-1] == v.rest$V1[-n.rest]))
    idx.one = sort(unique(c(idx.one,idx.one+1)))
    v.rest = v.rest[idx.one,]
    
    if(nrow(v.rest) == 0) next
    
    v.rest = v.rest[order(-v.rest$V3),]
    v.rest = v.rest[order(v.rest$V2),]
    v.rest = v.rest[order(v.rest$V8),]
    v.rest = v.rest[order(v.rest$V1),]
    # remove nestedness
    idx.nested = 1
    while(length(idx.nested) > 0){
      idx.nested = which((v.rest$V2[-1] >= v.rest$V2[-nrow(v.rest)]) & 
                           (v.rest$V3[-1] <=v.rest$V3[-nrow(v.rest)]) & 
                           (v.rest$V1[-1] == v.rest$V1[-nrow(v.rest)]) &
                           (v.rest$V8[-1] == v.rest$V8[-nrow(v.rest)])) + 1
      # print(length(idx.nested))
      if(length(idx.nested) == 0) next
      v.rest = v.rest[-idx.nested,]  
    }
    
    if(nrow(v.rest) == 0) next
    
    v.rest$cover = v.rest$V3 - v.rest$V2 + 1
    v.rest$overlap1 = c(v.rest$V2[-1] - v.rest$V3[-nrow(v.rest)] - 1, 0)
    v.rest$overlap1[v.rest$overlap1 > 0] = 0
    idx.diff = which(v.rest$V8[-1] != v.rest$V8[-nrow(v.rest)])
    v.rest$overlap1[idx.diff] = 0
    idx.diff = which(v.rest$V1[-1] != v.rest$V1[-nrow(v.rest)])
    v.rest$overlap1[idx.diff] = 0
    v.rest$cover = v.rest$cover + v.rest$overlap1
    
    v.rest$comb = paste(v.rest$V1, v.rest$V8, sep = s.tmp.comb)
    df.cover = data.frame(V1 = tapply(v.rest$V1, v.rest$comb, unique),
                          V2 = tapply(v.rest$V2, v.rest$comb, min),
                          V3 = tapply(v.rest$V3, v.rest$comb, max),
                          V4 = tapply(v.rest$V4, v.rest$comb, min),
                          V5 = tapply(v.rest$V5, v.rest$comb, max),
                          V6.old = tapply(v.rest$V6, v.rest$comb, mean),
                          V7 = tapply(v.rest$cover, v.rest$comb, sum), 
                          V8 = tapply(v.rest$V8, v.rest$comb, unique),
                          # comb = tapply(v.rest$comb, v.rest$comb, unique),
                          len1 = tapply(v.rest$len1, v.rest$comb, unique))
    
    # Fix V6
    cover.tot = aggregate((V6 / 100) * cover ~ comb, data = v.rest, sum) 
    rownames(cover.tot) = cover.tot$comb
    df.cover$V6 = cover.tot[rownames(df.cover), 2] / df.cover$V7 * 100
    
    # df.cover$dir = i.strand
    df.cover$ref.cover = df.cover$V5 - df.cover$V4 + 1
    rownames(df.cover) = NULL
    if(i.strand == 1){
      # tmp = df.cover$V4
      # df.cover$V4 = df.cover$V5
      # df.cover$V5 = tmp
      
      df.cover[,c('V4', 'V5')] = tmp.max - df.cover[,c('V4', 'V5')]
    }
    df.cover$V8 = sapply(df.cover$V8, function(s) strsplit(s, '\\|')[[1]][1])
    
    idx.include = (df.cover$V7 / df.cover$len1 > coverage) &  # CHANGED FROM sim.cutoff
                  (df.cover$V6 > sim.cutoff * 100) & 
                  (df.cover$ref.cover / df.cover$len1 > coverage) &   # CHANGED FROM sim.cutoff
                  (df.cover$len1 / df.cover$ref.cover > coverage)     # CHANGED FROM sim.cutoff
    
    # Add Strand
    df.cover$strand = s.strand[i.strand + 1]
    
    v.sim = rbind(v.sim, df.cover[idx.include, colnames(v.sim)])
  }
  return(v.sim)
}


#' Convert BLAST results to GFF format
#'
#' @description
#' `blastres2gff` converts a data frame containing BLAST results into a GFF formatted file.
#'
#' @param v.blast A data frame containing the BLAST results. Expected columns are V1, V4, V5, V7, V8, len1, and strand.
#' @param gff.file The file path where the GFF output will be saved.
#' @param to.sort Boolean value indicating whether the output should be sorted. If `TRUE` (default), 
#' the output is sorted by column 4 and then by column 1. If `FALSE`, the output is not sorted.
#'
#' @return This function does not return a value. It writes the GFF formatted data to a file specified by `gff.file`.
#'
#' @examples
#' # Example usage (assuming `blast_results` is your data frame with BLAST results):
#' blastres2gff(blast_results, "output.gff")
#' 
#' @author Anna A. Igolkina 
blastres2gff <- function(v.blast, gff.file, to.sort = T){
  v.gff = data.frame(col1 = v.blast$V8,
                     col2 = 'blast2gff',
                     col3 = 'query',
                     col4 = v.blast$V4,
                     col5 = v.blast$V5,
                     col6 = '.',
                     col7 = v.blast$strand,
                     col8 = '.',
                     col9 = paste0('ID=Q', 1:nrow(v.blast),
                                   ';query=',v.blast$V1,
                                   ';length=', v.blast$len1,
                                   ';similarity=', round(v.blast$V6, 1),
                                   ';coverage=', round(v.blast$V7 / v.blast$len1 * 100, 1) ))
  
  # Sorting
  if(to.sort){
    v.gff = v.gff[order(v.gff$col4),]
    v.gff = v.gff[order(v.gff$col1),]
  }
  writeGFF(v.gff, gff.file)
}

#' Find Nestedness in Data
#'
#' This function computes the nestedness of given data, considering strand direction if specified.
#' It rearranges sequence start and end positions based on strand direction, creates unique identifiers,
#' and computes coverage for each side of the data.
#'
#' @param v.res A data frame that should contain the following columns:
#'   - V1: An identifier column for sequences #1.
#'   - V2: A numeric column representing the start position of the sequences #1.
#'   - V3: A numeric column representing the end position of the sequences #1.

#'   - V8: An identifier column for sequences #2.
#'   - V4: A numeric column representing the start position of the sequences #2.
#'   - V5: A numeric column representing the end position of the sequences #2.

#' @param use.strand Logical, if TRUE, strand information is considered in the processing.
#'
#' @return Returns a data frame `v.cover` with the following structure:
#'   - C1, C8: Coverage data calculated for each side.
#'   - V1, V8:Identifiers of sequences..
#'   - dir: A column specifying the direction of the strand ('+', '-') if `use.strand` is TRUE, or '.'.
#'   - Additional columns might be included based on the implementation of `getOneSideCoverage` and other calculations within the function.
#'
#' @examples
#' # Example usage:
#' # result <- findNestedness(data, TRUE)
#'
#' @export
findNestedness <- function(v.res, use.strand = T){
  
  idx.strand = v.res$V4 > v.res$V5
  tmp = v.res$V4[idx.strand]
  v.res$V4[idx.strand] = v.res$V5[idx.strand]
  v.res$V5[idx.strand] = tmp
  
  
  # Make unique names for strands
  if(use.strand == T){
    str.strand = c('+', '-')
    dir.strand = str.strand[idx.strand * 1 + 1]
    v.res$V8 = paste(v.res$V8, dir.strand, sep = '|')
  } 
  v.res$comb = paste(v.res$V1, v.res$V8, sep = '||')
  
  v.res$V1 = v.res$comb
  v.res$V8 = v.res$comb
  cover1 = getOneSideCoverage(v.res)
  cover8 = getOneSideCoverage(v.res, side = 1)
  
  
  v.cover = data.frame(C1 = cover1)
  v.cover$C8 = cover8[rownames(v.cover)]
  v.cover[,c('V1', 'V8')] = stringr::str_split_fixed(rownames(v.cover), "\\|\\|", 2)
  rownames(v.cover) = NULL
  
  if(use.strand){
    v.cover$dir = substr(v.cover$V8, nchar(v.cover$V8), nchar(v.cover$V8))
    v.cover$V8 = substr(v.cover$V8, 1, (nchar(v.cover$V8) - 2))
  } else {
    v.cover$dir = '.'
  }
  
  return(v.cover)
  # v.nest = v.cover[(v.cover$p1 >= sim.cutoff) | (v.cover$p8 >= sim.cutoff),]
  
}

#' Calculate Coverage one sequence.
#'
#' @param v.rest A data frame that should contain the following columns:
#'   - V1: An identifier column for sequences #1.
#'   - V2: A numeric column representing the start position of the sequences #1.
#'   - V3: A numeric column representing the end position of the sequences #1.

#'   if `side = 1` is provided, then also:
#'   - V8: An identifier column for sequences #2.
#'   - V4: A numeric column representing the start position of the sequences #2.
#'   - V5: A numeric column representing the end position of the sequences #2.

#' @param side An integer indicating which side to consider for coverage calculation of #1 or of #2. 
#'             Defaults to 0, so coverage of sequences "#1.
#'
#' @return Returns a named vector where each name corresponds to an identifier in the V1 column,
#'         and each value is the sum of coverage values for that identifier.
#'
#' @export
getOneSideCoverage <- function(v.rest, side = 0){
  
  # print(head(v.rest))
  if(side == 1){
    
    
    idx.tmp = v.rest$V4 > v.rest$V5
    if(sum(idx.tmp) > 0){
      tmp = v.rest$V4[idx.tmp]
      v.rest$V4[idx.tmp] = v.rest$V5[idx.tmp]
      v.rest$V5[idx.tmp] = tmp
    }
    
    v.rest$V1 = v.rest$V8
    v.rest$V2 = v.rest$V4
    v.rest$V3 = v.rest$V5
    
  }
  v.rest = v.rest[, 1:3]
  # print(head(v.rest))
  
  # - - - - - - - - - - - - - - - - - - - - - - - - 
  
  v.rest = v.rest[order(-v.rest$V3),]
  v.rest = v.rest[order(v.rest$V2),]
  v.rest$V1 = as.factor(v.rest$V1)
  v.rest = v.rest[order(v.rest$V1),]
  
  # remove nestedness
  idx.nested = 1
  while(length(idx.nested) > 0){
    idx.nested = which((v.rest$V2[-1] >= v.rest$V2[-nrow(v.rest)]) & 
                         (v.rest$V3[-1] <=v.rest$V3[-nrow(v.rest)]) & 
                         (v.rest$V1[-1] == v.rest$V1[-nrow(v.rest)])) + 1
    # print(length(idx.nested))
    if(length(idx.nested) == 0) next
    v.rest = v.rest[-idx.nested,]  
  }
  
  v.rest$cover = v.rest$V3 - v.rest$V2 + 1
  v.rest$overlap = c(v.rest$V2[-1] - v.rest$V3[-nrow(v.rest)] - 1, 0)
  v.rest$overlap[v.rest$overlap > 0] = 0
  idx.diff = which(v.rest$V1[-1] != v.rest$V1[-nrow(v.rest)])
  v.rest$overlap[idx.diff] = 0
  v.rest$cover = v.rest$cover + v.rest$overlap
  
  coverage = tapply(v.rest$cover, v.rest$V1, sum)
  return(coverage)
}
















