#!/usr/bin/perl
##############################################################################
# Integration tests for filter_msp.pl utility script
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use FindBin qw($RealBin);

# Find the scripts
my $script_dir = File::Spec->catdir($RealBin, '..');
my $script = File::Spec->catfile($script_dir, 'filter_msp.pl');
my $test_msp = File::Spec->catfile($RealBin, 'data', 'minimal.msp');
my $test_peptides = File::Spec->catfile($RealBin, 'data', 'peptide_list.txt');
my $perl = $^X;

unless (-f $script) {
    plan skip_all => "Script not found: $script";
}
unless (-f $test_msp) {
    plan skip_all => "Test MSP file not found: $test_msp";
}
unless (-f $test_peptides) {
    plan skip_all => "Test peptide list not found: $test_peptides";
}

plan tests => 14;

# Create temp directory for output files
my $tmpdir = tempdir(CLEANUP => 1);

# Test 1: Script syntax check
{
    my $output = `"$perl" -c "$script" 2>&1`;
    like($output, qr/syntax OK/i, 'Script syntax is valid');
}

# Test 2: Help output
{
    my $output = `"$perl" "$script" --help 2>&1`;
    like($output, qr/Usage:|SYNOPSIS/i, 'Help output contains Usage or SYNOPSIS');
    like($output, qr/--input/i, 'Help output contains --input option');
    like($output, qr/--peptides/i, 'Help output contains --peptides option');
}

# Test 3: Version output
{
    my $output = `"$perl" "$script" --version 2>&1`;
    like($output, qr/version/i, 'Version output present');
}

# Test 4: Filter MSP file
{
    my $output_file = File::Spec->catfile($tmpdir, 'filtered.msp');
    my $cmd = qq{"$perl" "$script" -i "$test_msp" -p "$test_peptides" -o "$output_file" 2>&1};
    my $output = `$cmd`;
    
    ok(-f $output_file, 'Filtered output file created');
    
    if (-f $output_file) {
        # Check output content
        open(my $fh, '<', $output_file) or die "Cannot open $output_file: $!";
        my $content = do { local $/; <$fh> };
        close($fh);
        
        # Should contain IQVR and MLQGR (from peptide_list.txt)
        # Should NOT contain LKCASLQK or SCRSYR
        like($content, qr/Name:\s*IQVR\//, 'Output contains IQVR entry');
        like($content, qr/Name:\s*MLQGR\//, 'Output contains MLQGR entry');
        unlike($content, qr/Name:\s*LKCASLQK\//, 'Output does NOT contain LKCASLQK');
        unlike($content, qr/Name:\s*SCRSYR\//, 'Output does NOT contain SCRSYR');
    } else {
        fail('Output contains PEPTIDE entry');
        fail('Output contains TESTPEPTIDE entry');
        fail('Output does NOT contain MODPEPTIDE');
        fail('Output does NOT contain OXIDPEPTIDE');
        diag("Filtering output: $output");
    }
}

# Test 5: Statistics output
{
    my $output_file = File::Spec->catfile($tmpdir, 'stats_test.msp');
    my $cmd = qq{"$perl" "$script" -i "$test_msp" -p "$test_peptides" -o "$output_file" 2>&1};
    my $output = `$cmd`;
    
    like($output, qr/entries\s*(kept|processed)/i, 'Output shows statistics');
}

# Test 6: Error handling for missing input
{
    my $cmd = qq{"$perl" "$script" -i "nonexistent.msp" -p "$test_peptides" 2>&1};
    my $output = `$cmd`;
    
    like($output, qr/Cannot open|not found|error/i, 'Error message for missing input file');
}

# Test 7: Error handling for missing peptide list
{
    my $cmd = qq{"$perl" "$script" -i "$test_msp" -p "nonexistent.txt" 2>&1};
    my $output = `$cmd`;
    
    like($output, qr/Cannot open|not found|error/i, 'Error message for missing peptide file');
}

# Test 8: Empty peptide list results in empty output
{
    my $empty_list = File::Spec->catfile($tmpdir, 'empty_peptides.txt');
    open(my $fh, '>', $empty_list) or die "Cannot create $empty_list: $!";
    close($fh);
    
    my $output_file = File::Spec->catfile($tmpdir, 'empty_filtered.msp');
    my $cmd = qq{"$perl" "$script" -i "$test_msp" -p "$empty_list" -o "$output_file" 2>&1};
    my $output = `$cmd`;
    
    ok(-f $output_file, 'Output file created even with empty filter');
}

done_testing();
