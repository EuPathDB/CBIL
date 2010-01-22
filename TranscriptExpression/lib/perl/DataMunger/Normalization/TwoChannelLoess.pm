package CBIL::TranscriptExpression::DataMunger::Normalization::TwoChannelLoess;
use base qw(CBIL::TranscriptExpression::DataMunger::Normalization);

use strict;

use CBIL::TranscriptExpression::Utils;
use CBIL::TranscriptExpression::Error;

use File::Basename;

#--------------------------------------------------------------------------------

sub getGridRows                            { $_[0]->{gridRows} }
sub getGridColumns                         { $_[0]->{gridColumns} }
sub getSpotRows                            { $_[0]->{spotRows} }
sub getSpotColumns                         { $_[0]->{spotColumns} }

sub getGreenColumnName                     { $_[0]->{greenColumnName} }
sub getRedColumnName                       { $_[0]->{redColumnName} }
sub getFlagColumnName                      { $_[0]->{flagColumnName} }

sub getExcludeSpotsByFlagValue             { $_[0]->{excludeSpotsByFlagValue} }
sub getWithinSlideNormalizationType        { $_[0]->{withinSlideNormalizationType} }
sub getDoAcrossSlideNormalization          { $_[0]->{doAcrossSlideNormalization} }

#--------------------------------------------------------------------------------

sub new {
  my ($class, $args) = @_;

  my $self = $class->SUPER::new($args);

  my $additionalRequiredParams = ['greenColumnName',
                                  'redColumnName',
                                  'flagColumnName',
                                  'withinSlideNormalizationType',
                                  'gridRows',
                                  'gridColumns',
                                  'spotRows',
                                  'spotColumns',
                                 ];

  CBIL::TranscriptExpression::Utils::checkRequiredParams($additionalRequiredParams, $args);

  my $normType = $self->getWithinSlideNormalizationType();
  if($normType ne 'loess' && $normType ne 'printTipLoess' && $normType ne 'median') {
    CBIL::TranscriptExpression::Error->new("within slide normalizationType must be one of [loess,printTipLoess, or median]")->throw();
  }
  return $self;
}

sub munge {
  my ($self) = @_;

  my $dataFilesRString = $self->makeDataFilesRString();

  my $rFile = $self->writeRScript($dataFilesRString);

  $self->runR($rFile);

#  system("rm $rFile");
}


sub writeRScript {
  my ($self, $dataFilesString) = @_;

  my $mappingFile = $self->getMappingFile();
  my $outputFile = $self->getOutputFile();
  my $outputFileBase = basename($outputFile);
  my $pathToDataFiles = $self->getPathToDataFiles();

  my $ngr = $self->getGridRows();
  my $ngc = $self->getGridColumns();
  my $nsr = $self->getSpotRows();
  my $nsc = $self->getSpotColumns();

  my $gf = $self->getGreenColumnName();
  my $rf = $self->getRedColumnName();
  my $flags = $self->getFlagColumnName();

  my $normalizationType = $self->getWithinSlideNormalizationType();
  my $excludeFlagValue = $self->getExcludeSpotsByFlagValue();

  my $doAcrossSlideScaling = $self->getDoAcrossSlideNormalization() ? "TRUE" : "FALSE";

  my $rFile = "/tmp/$outputFileBase.R";

  open(RCODE, "> $rFile") or die "Cannot open $rFile for writing:$!";

  my $rString = <<RString;
load.marray = library(marray, logical.return=TRUE);

if(load.marray) {

source("$ENV{GUS_HOME}/lib/R/TranscriptExpression/normalization_functions.R");

my.layout = read.marrayLayout(ngr=$ngr, ngc=$ngc, nsr=$nsr, nsc=$nsc);
my.gnames = read.marrayInfo("$mappingFile", info.id=c(1,2), labels=1, na.strings=c(""))

data.files = vector();
$dataFilesString

raw.data = read.marrayRaw(data.files, path="$pathToDataFiles", name.Gf="$gf", name.Rf="$rf", name.W="$flags", layout=my.layout, gnames=my.gnames, skip=0);

# Rb and Gb slots need to hold a matrix of same dim as the Rf and Gf slots
raw.data\@maRb = raw.data\@maRf * 0;
raw.data\@maGb = raw.data\@maGf * 0;

# vector of rows to normalize on (ie. spots to use when drawing the loesss curve)
subsetOfGenes = !is.na(raw.data\@maGnames\@maInfo[,2]);

# set raw values for any flags to NA
flagged.values = setFlaggedValuesToNA(rM=raw.data\@maRf, gM=raw.data\@maGf, wM=raw.data\@maW, fv="$excludeFlagValue");
raw.data\@maRf = flagged.values\$R;
raw.data\@maGf = flagged.values\$G;

norm.data = maNorm(raw.data, norm=c("$normalizationType"), subset=subsetOfGenes, span=0.4, Mloc=TRUE, Mscale=TRUE, echo=FALSE);

if($doAcrossSlideScaling) {
 norm.data = maNormScale(norm.data, norm=c("globalMAD"), subset=TRUE, geo=TRUE,  Mscale=TRUE, echo=FALSE);
}

# Avg Spotted Replicates based on "genes" in Mapping File
avgM = aggregate(norm.data\@maM, list(norm.data\@maGnames\@maInfo[,2]), mean, na.rm=TRUE);

colnames(avgM) = c("ID", data.files);

# write data
write.table(avgM, file="$outputFile", quote=F, sep="\\t", row.names=FALSE);

} else {
  stop("ERROR:  could not load required marray library");
}
RString

  print RCODE $rString;

  close RCODE;

  return $rFile;
}


1;