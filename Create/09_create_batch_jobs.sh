#!/bin/bash
shopt -s nullglob dotglob

if [ $# -ne 2 ]
then
    echo "./09_create_batch_jobs.sh outdir max_n"
    exit -1
fi

outdir=$1
max_n=$2

dependencies=$outdir/dependencies.out
relations=$outdir/dependency_relations.dump

relations_basename=$(basename $relations)

mkdir -p $outdir/batch
cp $relations $outdir/batch/$relations_basename

# split dependencies.out into smaller files of 10,000 lines
split -a 3 -d -l 10000 $dependencies $outdir/batch/dependencies

i=0
j=0
infiles=""
nr=0
cd $outdir/batch
depfiles=(dependencies*)
for infile in ${depfiles[@]}
do
    i=$((i+1))
    j=$((j+1))
    if [ $i -eq 1 ]
    then
	infiles=$infile
    else
	infiles="$infiles $infile"
    fi
    if [ $i -eq 4 -o $j -eq ${#depfiles[@]} ]
    then
	i=0
	nr=$((nr+1))
	jobnr=$(printf "%03d" $nr)
	cat > subgraphjob_$jobnr.sh <<EOF
#!/bin/bash -l
#
# allocate 1 node (4 CPUs) for 10 hours
# sufficient for 100,000 sentences
#PBS -l nodes=1:ppn=4,walltime=10:00:00
#
# job name 
#PBS -N subgraphjob_$jobnr
#
# stdout and stderr files
#PBS -o job${jobnr}.out -e job${jobnr}.err
#
# first non-empty non-comment line ends PBS options

files=($infiles)
cd \$HOME/Pareidoscope/dependencies_batch
cp $relations_basename $infiles \$TMPDIR
cd \$TMPDIR

for (( i=0 ; i < \${#files[@]} ; i++ ))
do
    perl \$HOME/Pareidoscope/hpc_01_collect_dependency_subgraphs.pl \${files[\$i]} $relations_basename subgraphs_${jobnr}_\$i.txt $max_n &
done

# Don't execute the next command until subshells finish.
wait

for (( i=1 ; i <= $max_n ; i++ ))
do
    keys=""
    i_square=\$(( \$i ** 2 ))
    for (( j=1 ; j<=\$i_square ; j++))
    do
	keys="\$keys -k\$j,\$j"
    done
    percentage=\$(( 50 / $max_n ))
    # this is a tabulator:
    #grep -h "	\$i\$" subgraphs_${jobnr}_*.txt > \$FASTTMP/subgraphs_${jobnr}_\$i.txt &
    grep -h "	\$i\$" subgraphs_${jobnr}_*.txt | sort -S \${percentage}% -T \$TMPDIR -n \$keys | gzip > \$FASTTMP/subgraphs_${jobnr}_\$i.txt.gz &

done

wait

rm $infiles subgraphs_${jobnr}_*.txt
EOF
    fi
done
