#!/usr/bin/perl
##############################################################################
# Unit tests for MSP format parsing and generation
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use FindBin qw($RealBin);

# Find the main script
my $script_dir = File::Spec->catdir($RealBin, '..');
my $script = File::Spec->catfile($script_dir, 'blib2msp.pl');
my $test_unimod = File::Spec->catfile($RealBin, 'data', 'minimal_unimod.xml');

unless (-f $script) {
    plan skip_all => "Main script not found: $script";
}

plan tests => 20;

# Load the main script as a module
{
    package main;
    our $VERSION;
    do $script or die "Cannot load script: $@";
}

# Load test unimod file
main::load_unimod($test_unimod) if -f $test_unimod;

# Test 1: Function existence
ok(defined(&main::parse_comment), 'parse_comment function exists');
ok(defined(&main::format_msp_entry), 'format_msp_entry function exists');
ok(defined(&main::extract_peaks), 'extract_peaks function exists');

# Test 2: parse_comment with simple input
{
    my %fields = main::parse_comment('Parent=617.284 Mods=0 RetentionTime=123.45 Score=0.99');
    is($fields{Parent}, '617.284', 'Parse Parent from Comment');
    is($fields{Mods}, '0', 'Parse Mods from Comment');
    is($fields{RetentionTime}, '123.45', 'Parse RetentionTime from Comment');
    is($fields{Score}, '0.99', 'Parse Score from Comment');
}

# Test 3: parse_comment with modifications
{
    my %fields = main::parse_comment('Parent=500.25 Mods=2(3,C,Carbamidomethyl)(7,M,Oxidation)');
    is($fields{Parent}, '500.25', 'Parse Parent with mods');
    is($fields{Mods}, '2(3,C,Carbamidomethyl)(7,M,Oxidation)', 'Parse complex Mods string');
}

# Test 4: parse_comment with quoted values
{
    my %fields = main::parse_comment('Parent=617.284 Protein="sp|TRYP_PIG| Trypsin" Score=0.95');
    is($fields{Parent}, '617.284', 'Parse Parent before quoted');
    is($fields{Protein}, 'sp|TRYP_PIG| Trypsin', 'Parse quoted Protein value');
    is($fields{Score}, '0.95', 'Parse Score after quoted');
}

# Test 5: parse_comment with protein accession
{
    my %fields = main::parse_comment('Parent=500.0 Protein=sp|P12345| MultiProtein=1');
    is($fields{Protein}, 'sp|P12345|', 'Parse unquoted Protein');
    is($fields{MultiProtein}, '1', 'Parse MultiProtein flag');
}

# Test 6: format_msp_entry basic output
{
    my $row = {
        peptideSeq => 'PEPTIDE',
        peptideModSeq => 'PEPTIDE',
        precursorMZ => 400.7006,
        precursorCharge => 2,
        retentionTime => 2.0,  # minutes
        score => 0.95,
        scoreType => 1,
    };
    my @mz = (175.119, 288.203, 401.287);
    my @intensity = (1000.0, 800.0, 600.0);
    my @mods = ();
    my %score_types = (1 => 'PERCOLATOR QVALUE');
    my @proteins = ();
    
    my $output = main::format_msp_entry($row, \@mz, \@intensity, \@mods, \%score_types, \@proteins);
    
    like($output, qr/^Name: PEPTIDE\/2_0$/m, 'Name line format correct');
    like($output, qr/^MW: \d+\.\d+$/m, 'MW line present');
    like($output, qr/^Comment:.*Parent=400\.7006/m, 'Comment contains Parent');
    like($output, qr/^Comment:.*Mods=0/m, 'Comment contains Mods=0');
    like($output, qr/^Num peaks: 3$/m, 'Num peaks correct');
}

# Test 7: format_msp_entry with protein
{
    my $row = {
        peptideSeq => 'TESTPEP',
        peptideModSeq => 'TESTPEP',
        precursorMZ => 380.2,
        precursorCharge => 2,
    };
    my @mz = (100.0);
    my @intensity = (500.0);
    my @mods = ();
    my %score_types = ();
    my @proteins = ('P12345');
    
    my $output = main::format_msp_entry($row, \@mz, \@intensity, \@mods, \%score_types, \@proteins);
    
    like($output, qr/Protein=sp\|P12345\|/, 'Protein field formatted correctly');
}

done_testing();
