#!/usr/bin/perl
##############################################################################
# Integration tests for extract_peptides.pl utility script
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use FindBin qw($RealBin);

# Find the scripts
my $script_dir = File::Spec->catdir($RealBin, '..');
my $script = File::Spec->catfile($script_dir, 'extract_peptides.pl');
my $test_msp = File::Spec->catfile($RealBin, 'data', 'minimal.msp');
my $test_blib = File::Spec->catfile($RealBin, 'data', 'minimal.blib');
my $perl = $^X;

unless (-f $script) {
    plan skip_all => "Script not found: $script";
}
unless (-f $test_msp) {
    plan skip_all => "Test MSP file not found: $test_msp";
}

plan tests => 15;

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
}

# Test 3: Version output
{
    my $output = `"$perl" "$script" --version 2>&1`;
    like($output, qr/version/i, 'Version output present');
}

# Test 4: Extract peptides from MSP file
{
    my $output_file = File::Spec->catfile($tmpdir, 'extracted_peptides.txt');
    my $cmd = qq{"$perl" "$script" -i "$test_msp" -o "$output_file" 2>&1};
    my $output = `$cmd`;
    
    ok(-f $output_file, 'Output file created');
    
    if (-f $output_file) {
        # Check output content
        open(my $fh, '<', $output_file) or die "Cannot open $output_file: $!";
        my @peptides = <$fh>;
        close($fh);
        
        ok(scalar(@peptides) > 0, 'Output file has peptides');
        
        # Check for expected peptides from minimal.msp
        my %found = map { chomp; $_ => 1 } @peptides;
        ok($found{IQVR}, 'Found IQVR in output');
        ok($found{MLQGR}, 'Found MLQGR in output');
    } else {
        fail('Output file has peptides');
        fail('Found PEPTIDE in output');
        fail('Found TESTPEPTIDE in output');
        diag("Extraction output: $output");
    }
}

# Test 5: Auto-generate output filename
{
    # Copy test file to temp dir to test auto-naming
    my $temp_msp = File::Spec->catfile($tmpdir, 'test_lib.msp');
    {
        open(my $in, '<', $test_msp) or die "Cannot open $test_msp: $!";
        open(my $out, '>', $temp_msp) or die "Cannot open $temp_msp: $!";
        print $out $_ while <$in>;
        close($in);
        close($out);
    }
    
    my $cmd = qq{cd "$tmpdir" && "$perl" "$script" -i "test_lib.msp" 2>&1};
    my $output = `$cmd`;
    
    my $expected_output = File::Spec->catfile($tmpdir, 'test_lib_peptides.txt');
    ok(-f $expected_output, 'Auto-generated output file created');
}

# Test 6: Error handling for missing input
{
    my $cmd = qq{"$perl" "$script" -i "nonexistent_file.msp" 2>&1};
    my $output = `$cmd`;
    
    like($output, qr/Cannot open|not found|error/i, 'Error message for missing file');
}

# Test 7: Count unique peptides
{
    my $output_file = File::Spec->catfile($tmpdir, 'count_test.txt');
    my $cmd = qq{"$perl" "$script" -i "$test_msp" -o "$output_file" 2>&1};
    my $output = `$cmd`;
    
    like($output, qr/\d+\s+unique/i, 'Output shows unique peptide count');
}

# Test 8: Sorted output
{
    my $output_file = File::Spec->catfile($tmpdir, 'sorted_test.txt');
    my $cmd = qq{"$perl" "$script" -i "$test_msp" -o "$output_file" 2>&1};
    my $output = `$cmd`;
    
    if (-f $output_file) {
        open(my $fh, '<', $output_file) or die "Cannot open $output_file: $!";
        my @peptides = <$fh>;
        close($fh);
        
        my @sorted = sort @peptides;
        my $is_sorted = join('', @peptides) eq join('', @sorted);
        ok($is_sorted, 'Output is sorted alphabetically');
    } else {
        fail('Output is sorted alphabetically');
    }
}

# Test 9: Extract from BLIB file
SKIP: {
    skip "Test BLIB file not found", 3 unless -f $test_blib;
    
    my $output_file = File::Spec->catfile($tmpdir, 'blib_peptides.txt');
    my $cmd = qq{"$perl" "$script" -i "$test_blib" -o "$output_file" 2>&1};
    my $output = `$cmd`;
    
    ok(-f $output_file, 'BLIB extraction output file created');
    
    if (-f $output_file) {
        open(my $fh, '<', $output_file) or die "Cannot open $output_file: $!";
        my @peptides = <$fh>;
        close($fh);
        
        my %found = map { chomp; $_ => 1 } @peptides;
        ok($found{IQVR}, 'Found IQVR from BLIB');
        ok($found{MLQGR}, 'Found MLQGR from BLIB');
    } else {
        fail('Found IQVR from BLIB');
        fail('Found MLQGR from BLIB');
        diag("BLIB extraction output: $output");
    }
}

done_testing();
