#!/usr/bin/perl
##############################################################################
# Unit tests for error handling paths in blib2msp.pl
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

unless (-f $script) {
    plan skip_all => "Main script not found: $script";
}

plan tests => 16;

# Load the main script as a module
{
    package main;
    our $VERSION;
    do $script or die "Cannot load script: $@";
}

# Test 1: lookup_unimod_name with edge cases
{
    # Reset unimod state
    $main::UNIMOD_LOADED = 0;
    
    # Lookup before loading should return undef
    my $result = main::lookup_unimod_name(57.021);
    is($result, undef, 'lookup_unimod_name returns undef when unimod not loaded');
    
    # Lookup with undef
    $result = main::lookup_unimod_name(undef);
    is($result, undef, 'lookup_unimod_name returns undef for undef mass');
}

# Test 2: lookup_unimod_mass with edge cases
{
    # Reset unimod state
    $main::UNIMOD_LOADED = 0;
    
    my $result = main::lookup_unimod_mass('Carbamidomethyl');
    is($result, undef, 'lookup_unimod_mass returns undef when unimod not loaded');
    
    $result = main::lookup_unimod_mass(undef);
    is($result, undef, 'lookup_unimod_mass returns undef for undef name');
}

# Test 3: parse_modifications_from_string with edge cases
{
    my @mods = main::parse_modifications_from_string(undef);
    is(scalar(@mods), 0, 'parse_modifications_from_string handles undef');
    
    @mods = main::parse_modifications_from_string('');
    is(scalar(@mods), 0, 'parse_modifications_from_string handles empty string');
    
    @mods = main::parse_modifications_from_string('invalid format');
    is(scalar(@mods), 0, 'parse_modifications_from_string handles invalid format');
}

# Test 4: parse_comment with edge cases
{
    my %fields = main::parse_comment('');
    is(scalar(keys %fields), 0, 'parse_comment handles empty string');
    
    %fields = main::parse_comment('NoEquals');
    is(scalar(keys %fields), 0, 'parse_comment handles string without key=value');
    
    %fields = main::parse_comment('Key=Value');
    is($fields{Key}, 'Value', 'parse_comment handles simple key=value');
}

# Test 5: extract_peaks with edge cases
{
    my ($mz_ref, $int_ref) = main::extract_peaks(undef, undef, 0);
    ok(!defined $mz_ref || scalar(@$mz_ref) == 0, 'extract_peaks handles undef blobs');
    
    # Empty but defined blobs
    ($mz_ref, $int_ref) = main::extract_peaks('', '', 0);
    ok(!defined $mz_ref || scalar(@$mz_ref) == 0, 'extract_peaks handles empty blobs');
}

# Test 6: format_duration with edge cases
{
    my $result = main::format_duration(0);
    like($result, qr/0 seconds/, 'format_duration handles 0');
    
    $result = main::format_duration(59);
    like($result, qr/59 seconds/, 'format_duration handles 59 seconds');
    
    $result = main::format_duration(60);
    like($result, qr/1 min 0 sec/, 'format_duration handles exactly 60 seconds');
}

# Test 7: build_fasta_peptide_index with nonexistent directory
{
    my %index = main::build_fasta_peptide_index('/nonexistent/path/to/fasta');
    is(scalar(keys %index), 0, 'build_fasta_peptide_index returns empty hash for bad path');
}

done_testing();
