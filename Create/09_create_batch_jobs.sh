#!/bin/bash

if [ $# -ne 3 ]
then
    echo "./09_create_batch_jobs.sh outdir max_n"
    exit -1
fi

outdir=$1
dependencies=$outdir/dependencies.out
relations=$outdir/dependency_relations.dump
max_n=$4

relations_basename=$(basename $relations)

mkdir $outdir/batch
cp $relations $outdir/batch/$relations_basename

# split dependencies.out into smaller files of 25,000 lines
split -a 3 -d -l 25000 $dependencies $outdir/batch/dependencies

i=0
infiles=""
nr=0
cd $outdir/batch
for infile in dependencies*
do
    i=$((i+1))
    if [ $i -eq 1 ]
    then
	infiles=$infile
    elif [ $i -gt 1 -a $i -lt 4 ]
    then
	infiles="$infiles $infile"
    elif [ $i -eq 4 ]
    then
	infiles="$infiles $infile"
	i=0
	nr=$((nr+1))
	jobnr=$(printf "%03d" $nr)
	cat > subgraphjob_$jobnr.sh <<EOF
#!/bin/bash -l
#
# allocate 1 node (4 CPUs) for 3 hours
# sufficient for 100,000 sentences
#PBS -l nodes=1:ppn=4,walltime=03:00:00
#
# job name 
#PBS -N subgraphjob_$jobnr
#
# stdout and stderr files
#PBS -o job${jobnr}.out -e job${jobnr}.err
#
# first non-empty non-comment line ends PBS options

files=($infiles)
cd \$HOME/dependencies_batch
cp $relations_basename $infiles \$TMPDIR
cd \$TMPDIR

for (( i=0 ; i < \${#files[@]} ; i++ ))
do
    perl hpc_01_collect_dependency_subgraphs.pl \${files[\$i]} $relations_basename subgraphs_${jobnr}_\$i.txt $max_n &
done

# Don't execute the next command until subshells finish.
wait

for (( i=1 ; i <= $max_n ; i++ ))
do
    grep "\\t\$i\$" subgraphs_${jobnr}_*.txt > \$FASTTMP/subgraphs_${jobnr}_\$i.txt &
done

wait

rm $infiles subgraphs_${jobnr}_*.txt
EOF
    fi
done
