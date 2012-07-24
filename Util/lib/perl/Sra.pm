package CBIL::Util::Sra;

use LWP::Simple; 
use XML::Simple; 
use Data::Dumper; 

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(getRunIdsFromSraSampleIds getFastqForSraRunId getFastqForSampleIds);


sub getFastqForSampleIds {
  my($sids,$fileoutone,$fileouttwo,$dontdownload) = @_;
  $fileoutone = $fileoutone ? $fileoutone : "reads_1.fastq";
  $fileouttwo = $fileouttwo ? $fileouttwo : "reads_2.fastq";
  my @rids;
  foreach my $sid (@{$sids}){
    push(@rids,&getRunIdsFromSraSampleId($sid));
  }
  my @out;
  my $readCount = 0;
  my $fid = $rids[0]->[0];
  my $numEnds = 0;
  foreach my $a (@rids){
    push(@out,"$a->[0]:$a->[1]:".($a->[1] ? $a->[2] / $a->[1] : 'undef'));
    $readCount += $a->[1];
    my $id = $a->[0];
    next if $dontdownload;
    &getFastqForSraRunId($id);
    ##if single end will have single fastq file labeled _1.fastq .. otherwise two labeled _1 and _2.fastq
    my $tmpEnds = 0;
    my $foundFile = 0;
    if(-e "$id\_1.fastq"){
      $tmpEnds = 1;
      $foundFile++;
      if($fid ne $id){
        system("cat $id\_1.fastq >> $fid\_1.fastq");
        unlink("$id\_1.fastq");
      }
    }
    if(-e "$id\_2.fastq"){
      $foundFile++;
      $tmpEnds = 2;
      if($fid ne $id){
        system("cat $id\_2.fastq >> $fid\_2.fastq");
        unlink("$id\_2.fastq");
      }
    }
    if($numEnds){
      die "ERROR: runIds have mix of single and paired ends\n" if $numEnds != $tmpEnds;
    }else{
      $numEnds = $tmpEnds;
    }
  }
         print "SampleIds: (",join(", ",@{$sids}),") ", scalar(@rids) , " runs, $readCount spots: " , (scalar(@rids) == 0 ? "ERROR: unable to retrieve runIds\n" : "(",join(", ",@out),")\n");
  ##now mv the files to a final filename ...
#  rename("$fid.fastq","reads.fastq") if (-e "$fid.fastq");
  rename("$fid\_1.fastq","$fileoutone") if (-e "$fid\_1.fastq");
  rename("$fid\_2.fastq","$fileouttwo") if (-e "$fid\_2.fastq");
}

sub getRunIdsFromSraSampleId { 
 my ($sid) = @_; 

 my $utils = "http://www.ncbi.nlm.nih.gov/entrez/eutils"; 

 my $db     = "sra"; 
 my $report = "xml"; 

 my $esearch = "$utils/esearch.fcgi?db=$db&retmax=1&usehistory=y&term="; 
 my $esearch_result = get($esearch . $sid); 

# print $esearch_result;

 $esearch_result =~ 
m|<Count>(\d+)</Count>.*<QueryKey>(\d+)</QueryKey>.*<WebEnv>(\S+)</WebEnv>|s; 

 my $Count    = $1; 
 my $QueryKey = $2; 
 my $WebEnv   = $3; 

 my $efetch = "$utils/efetch.fcgi?rettype=$report&retmode=text&retmax=$Count&db=$db&query_key=$QueryKey&WebEnv=$WebEnv"; 

# print "\n--------------\n$efetch\n--------------\n";

 my $efetch_result = get($efetch); 

 my $root = XMLin($efetch_result); 

# print Dumper $root; 
# exit;
 
 my @ids;
 my @expPa;
 my $ep = $root->{'EXPERIMENT_PACKAGE'};
 if(ref($ep) eq 'ARRAY'){
   foreach my $a (@{$ep}){
     push(@expPa,$a);
   }
 }else{
   push(@expPa,$ep);
 }
 foreach my $e (@expPa){
   my @runsets;
   if(ref($e->{RUN_SET}) eq 'ARRAY'){
     foreach my $a (@{$e->{RUN_SET}}){
       push(@runsets,$a);
     }
   }else{
     push(@runsets,$e->{RUN_SET});
   }
   foreach my $rs (@runsets){
     my $rs = $e->{RUN_SET};
     if(ref($rs->{RUN}) eq 'ARRAY'){
       foreach my $r (@{$rs->{RUN}}){
         push(@ids, [$r->{accession},$r->{total_spots},$r->{total_bases}]);
       }
     }else{
       push(@ids, [$rs->{RUN}->{accession},$rs->{RUN}->{total_spots},$rs->{RUN}->{total_bases}]);
     }
   }
 }
 return @ids;
}

##do wget, then split files with fastq-dump, delete .sra when complete and also the barcode if relevant
## wget ftp://ftp-trace.ncbi.nlm.nih.gov/sra/sra-instant/reads/ByRun/sra/SRR/SRR340/SRR340131/SRR340131.sra
## http://ftp-private.ncbi.nlm.nih.gov/sra/sra-instant/reads/ByRun/sra/SRR/SRR016/SRR016080/SRR016080.sra
## looks like a problem to construct .. look for full path in sample.xml
## fastq-dump --split-files SRR340224.sra

sub getFastqForSraRunId {
  my($runId,$pe) = @_;
  my $file = "$runId.sra";
  my $cmd = "wget http://ftp-private.ncbi.nlm.nih.gov/sra/sra-instant/reads/ByRun/sra/".substr($runId,0,3)."/".substr($runId,0,6)."/$runId/$file";
  print STDERR "retrieving $runId with $cmd\n";
  system($cmd);
  if($?){
    print STDERR "ERROR ($?): Unable to fetch sra file for $runId\n";
    return;
  }
  print STDERR "extracting fastq file(s)...";
  system("fastq-dump --split-files $file");
  my @files = glob("$runId*.fastq");
  print STDERR "DONE: ".scalar(@files)." files (".join(", ",@files).")\n";
  unlink($file);
}

1;