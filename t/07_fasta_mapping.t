#!/usr/bin/perl
##############################################################################
# Unit tests for FASTA parsing and protein mapping
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use FindBin qw($RealBin);

# Find the main script
my $script_dir = File::Spec->catdir($RealBin, '..');
my $script = File::Spec->catfile($script_dir, 'blib2msp.pl');
my $test_fasta_dir = File::Spec->catfile($RealBin, 'data');
my $test_fasta = File::Spec->catfile($test_fasta_dir, 'test.fasta');

unless (-f $script) {
    plan skip_all => "Main script not found: $script";
}
unless (-f $test_fasta) {
    plan skip_all => "Test FASTA file not found: $test_fasta";
}

plan tests => 15;

# Load the main script as a module
{
    package main;
    our $VERSION;
    do $script or die "Cannot load script: $@";
}

# Test 1: Function existence
ok(defined(&main::build_fasta_peptide_index), 'build_fasta_peptide_index function exists');
ok(defined(&main::search_fasta_for_peptide), 'search_fasta_for_peptide function exists');

# Test 2: Build FASTA index
{
    my %index = main::build_fasta_peptide_index($test_fasta_dir);
    ok(scalar(keys %index) > 0, 'FASTA index built with proteins');
    ok(exists $index{'TRYP_PIG'}, 'Index contains TRYP_PIG accession');
    ok(exists $index{'CATA_HUMAN'}, 'Index contains CATA_HUMAN accession');
    ok(exists $index{'ALBU_HUMAN'}, 'Index contains ALBU_HUMAN accession');
}

# Test 3: Search for peptide IQVR (in TRYP_PIG)
{
    my @accessions = main::search_fasta_for_peptide($test_fasta_dir, 'IQVR');
    ok(scalar(@accessions) > 0, 'Found proteins containing IQVR');
    
    # IQVR appears in TRYP_PIG - verify we got results
    ok(scalar(@accessions) >= 1, 'Found expected protein(s) with IQVR');
}

# Test 4: Search for specific peptide MLQGR (in CATA_HUMAN)
{
    my @accessions = main::search_fasta_for_peptide($test_fasta_dir, 'MLQGR');
    ok(scalar(@accessions) > 0, 'Found proteins containing MLQGR');
    
    # Verify we found at least one protein
    ok(scalar(@accessions) >= 1, 'Found protein(s) containing MLQGR');
}

# Test 5: Search for non-existent peptide
{
    my @accessions = main::search_fasta_for_peptide($test_fasta_dir, 'ZZZZNOTFOUNDZZZ');
    is(scalar(@accessions), 0, 'No results for non-existent peptide');
}

# Test 6: Handle invalid directory
{
    my %index = main::build_fasta_peptide_index('/nonexistent/path');
    is(scalar(keys %index), 0, 'Empty index for non-existent directory');
    
    my @accessions = main::search_fasta_for_peptide('/nonexistent/path', 'PEPTIDE');
    is(scalar(@accessions), 0, 'No results for non-existent directory');
}

# Test 7: Peptide appearing in multiple proteins
{
    my @accessions = main::search_fasta_for_peptide($test_fasta_dir, 'SCRSYR');
    # SCRSYR appears multiple times in K2M3_SHEEP
    ok(scalar(@accessions) >= 1, 'Found at least one protein with SCRSYR');
}

# Test 8: Check for LKCASLQK (appears in ALBU_HUMAN)
{
    my @accessions = main::search_fasta_for_peptide($test_fasta_dir, 'LKCASLQK');
    # LKCASLQK should be found in ALBU_HUMAN
    ok(scalar(@accessions) >= 1, 'Found protein(s) containing LKCASLQK');
}

done_testing();
