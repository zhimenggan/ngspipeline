package CO::NGSPipeline::RNAseq::Common;

##############################################################################
# provide command method for each pipeline. It is a base module for all specific
# pipelines.

use strict;
use CO::NGSPipeline::RNAseq::Config;
use CO::NGSPipeline::Config;
use CO::NGSPipeline::Utils;
use File::Basename;

sub rnaseqqc {
	my $self = shift;
	
	my %param = ( "bam" => undef,
	              "sample_id" => undef,
	              @_);
	
	my $bam    = to_abs_path( $param{bam} );
	my $sample_id = $param{sample_id};
	
	my $pipeline = $self->{pipeline};
	
	my $bam_base = basename($bam);
	my $bam_rg = "$bam_base.RG.bam";
	my $bam_reorder = "$bam_base.reorder.bam";
	
	open OUT, ">$pipeline->{dir}/sample_list";
	print OUT "Sample ID	Bam File	Notes\n";
	print OUT "$sample_id\t$bam_reorder\tNo Note\n";
	close OUT;
	
	$pipeline->add_command("picard.sh AddOrReplaceReadGroups INPUT=$bam OUTPUT=$bam_rg RGID=readGroup_name RGLB=readGroup_name RGPL=illumina RGPU=run RGSM=sample_name SORT_ORDER=coordinate CREATE_INDEX=true TMP_DIR=$pipeline->{tmp_dir}");
	$pipeline->add_command("picard.sh ReorderSam INPUT=$bam_rg OUTPUT=$bam_reorder CREATE_INDEX=true R=$GENOME_HG19 TMP_DIR=$pipeline->{tmp_dir}");
	$pipeline->del_file("$bam_rg", "$bam_base.RG.bai");
	$pipeline->add_command("java -jar /home/guz/GenePatternServer/taskLib/RNASeQC.2.0/RNAseqMetrics.jar -s $pipeline->{dir}/sample_list -t $GENCODE_GTF -r $GENOME_HG19 -n 1000 -o $pipeline->{dir}/rnaseqqc");
	$pipeline->del_file("$bam_reorder", "$bam_base.reorder.bai");
	
	my $qid = $pipeline->run("-N" => $pipeline->get_job_name ? $pipeline->get_job_name : "_common_rnaseqqc",
							 "-l" => { nodes => "1:ppn=1:lsdf", 
									    mem => "20GB",
										walltime => "40:00:00"});
	return($qid);

}

sub rpkm {
	my $self = shift;
	
	my %param = ( "bam" => undef,
	              "strand" => 0,
	              @_);
	
	my $bam    = to_abs_path( $param{bam} );
	my $strand = $param{"strand"};
	
	my $bam_prefix = $bam;
	$bam_prefix =~s/\.bam$//;
	
	my $stand_opt = $strand ? "-S" : "";
	
	my $pipeline = $self->{pipeline};
	
	open OUT, ">$pipeline->{tmp_dir}/exonCoverage.sh";
	print OUT <<SH;
samtools view  -bu -q 1 $bam | coverageBed $stand_opt -split -abam stdin -b /icgc/ngs_share/assemblies/hg19_GRCh37_1000genomes/databases/RefSeq/RefSeq_Nov15_2011_from_annovar_Exons_plain.bed.gz > $bam_prefix.Exons_RPKM.bed.tmp

mv $bam_prefix.Exons_RPKM.bed.tmp $bam_prefix.Exons_RPKM.bed
total=\$(awk '{a+=\$(NF-3);}END{print a}' $bam_prefix.Exons_RPKM.bed)
echo -e "#chrom\tchromStart\tchromEnd\tname\tstrand\texonNr\tlength\treads\tbases_covered\tlength\tcoverage\tRPKM" > $bam_prefix.Exons_RPKM.bed.tmp
perl /icgc/ngs_share/ngsPipelines/tools/RPKM.pl $bam_prefix.Exons_RPKM.bed \$total | sort -k1,1d -k2,2n >> $bam_prefix.Exons_RPKM.bed.tmp
mv $bam_prefix.Exons_RPKM.bed.tmp $bam_prefix.Exons_RPKM.bed
bgzip -c -d /icgc/ngs_share/assemblies/hg19_GRCh37_1000genomes/databases/RefSeq/RefSeq_Nov15_2011_from_annovar_Genes_plain.bed.gz | perl /icgc/ngs_share/ngsPipelines/ExonCoverage/countcoverageBedRPKM.pl $bam_prefix.Exons_RPKM.bed - \$total | awk 'NR==1; NR > 1 {print \$0 | "sort -k1,1d -k2,2n"}' > $bam_prefix.Genes_RPKM.bed.tmp
mv $bam_prefix.Genes_RPKM.bed.tmp $bam_prefix.Genes_RPKM.bed

SH
	close OUT;
	
	$pipeline->add_command("sh $pipeline->{tmp_dir}/exonCoverage.sh");
	
	my $qid = $pipeline->run("-N" => $pipeline->get_job_name ? $pipeline->get_job_name : "_common_RPKM",
							 "-l" => { nodes => "1:ppn=1:lsdf", 
									    mem => "10GB",
										walltime => "10:00:00"});
	return($qid);
}

sub counting {
	my $self = shift;
	
	my %param = ( "bam" => undef,
	              "strand" => 0,
	              @_);
	
	my $bam    = to_abs_path( $param{bam} );
	my $strand = $param{"strand"} ? "yes" : "no";
	
	my $bam_prefix = $bam;
	$bam_prefix =~s/\.bam$//;
	
	my $pipeline = $self->{pipeline};
	
	$pipeline->add_command("samtools sort -n $bam $bam.namesorted");
 	$pipeline->add_command("samtools view $bam.namesorted.bam | htseq-count -s $strand -t gene - $GENCODE_GTF > $bam_prefix.gene.count");
 	$pipeline->add_command("samtools view $bam.namesorted.bam | htseq-count -s $strand -t exon - $GENCODE_GTF > $bam_prefix.exon.count");
	$pipeline->del_file("$bam.namesorted.bam");

	my $qid = $pipeline->run("-N" => $pipeline->get_job_name ? $pipeline->get_job_name : "_common_counting",
							 "-l" => { nodes => "1:ppn=1:lsdf", 
									    mem => "10GB",
										walltime => "100:00:00"});
	return($qid);
}

1;