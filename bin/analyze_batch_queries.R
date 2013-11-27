#!/usr/bin/Rscript

args <- commandArgs(TRUE)

data <- read.table(args[1], sep = "\t", strip.white = TRUE, header = TRUE)
pdf(paste(args[1], ".pdf", sep=""))
boxplot(data, ylab = "MI (base 2)", main = args[2])
dev.off()
