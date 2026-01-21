#!/usr/bin/perl
##############################################################################
# Test runner for BLIB/MSP converter
##############################################################################

use strict;
use warnings;
use File::Spec;

my $perl = $^X;

# Get test files (Windows-compatible)
opendir(my $dh, 't') or die "Cannot open t directory: $!";
my @test_files = sort grep { /\.t$/ } readdir($dh);
closedir($dh);
@test_files = map { File::Spec->catfile('t', $_) } @test_files;

if (@test_files == 0) {
    print "No test files found in t/\n";
    exit 1;
}

print "=" x 60, "\n";
print "Running tests for BLIB/MSP Converter\n";
print "=" x 60, "\n\n";

my $total_pass = 0;
my $total_fail = 0;
my $total_skip = 0;

for my $test_file (@test_files) {
    print "Running: $test_file\n";
    print "-" x 40, "\n";
    
    my $output = `"$perl" "$test_file" 2>&1`;
    print $output;
    
    # Parse TAP output for summary
    if ($output =~ /^ok\s+\d+/m) {
        my @ok = ($output =~ /^ok\s+\d+/gm);
        my @not_ok = ($output =~ /^not ok\s+\d+/gm);
        my @skip = ($output =~ /^ok\s+\d+\s+#\s+skip/gim);
        
        $total_pass += scalar(@ok) - scalar(@skip);
        $total_fail += scalar(@not_ok);
        $total_skip += scalar(@skip);
    }
    
    print "\n";
}

print "=" x 60, "\n";
print "Test Summary\n";
print "=" x 60, "\n";
print "  Passed:  $total_pass\n";
print "  Failed:  $total_fail\n";
print "  Skipped: $total_skip\n";
print "=" x 60, "\n";

exit($total_fail > 0 ? 1 : 0);

