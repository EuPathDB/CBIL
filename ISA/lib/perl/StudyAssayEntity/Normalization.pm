package CBIL::ISA::StudyAssayEntity::Normalization;
use base qw(CBIL::ISA::StudyAssayEntity::Fileable);

use strict;

sub getParents {
  return ["Assay", "GelElectrophoresisAssay", "MSAssay", "NMRAssay", "HybridizationAssay"];
}

1;
