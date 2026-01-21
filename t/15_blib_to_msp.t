#!/usr/bin/perl
##############################################################################
# Unit tests for BLIB to MSP conversion
# Tests convert_blib_to_msp conversion by calling script and validating output
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use DBI;
use Compress::Zlib;

# Script path - try both relative to test dir and project root
my $script = File::Spec->catfile($RealBin, '..', 'blib2msp.pl');
unless (-f $script) {
    $script = 'blib2msp.pl';  # Try from project root
}
my $perl = $^X;

unless (-f $script) {
    plan skip_all => "blib2msp.pl not found";
}

# Test data files
my $test_blib = File::Spec->catfile($RealBin, 'data', 'minimal.blib');
unless (-f $test_blib) {
    # Try to create it
    my $create_script = File::Spec->catfile($RealBin, 'data', 'create_test_blib.pl');
    if (-f $create_script) {
        system($^X, $create_script);
    }
}

unless (-f $test_blib) {
    plan skip_all => "Test BLIB file not found: $test_blib";
}

# Create temp directory for output
my $tmpdir = tempdir(CLEANUP => 1);

plan tests => 47;

# Helper function to run conversion
sub run_conversion {
    my ($input, $output) = @_;
    my $cmd = qq{"$perl" "$script" -i "$input" -o "$output" 2>&1};
    my $exit_code = system($cmd);
    return $exit_code == 0;
}

# Test 1: Basic conversion - file creation
{
    my $output_msp = File::Spec->catfile($tmpdir, 'test_basic.msp');
    my $result = run_conversion($test_blib, $output_msp);
    
    ok($result, 'BLIB to MSP conversion succeeded');
    ok(-f $output_msp, 'MSP output file created');
    
    if (-f $output_msp) {
        my $size = -s $output_msp;
        ok($size > 0, 'MSP output file has content') or diag("File size: $size");
    }
}

# Test 2: Parse MSP output and verify structure
{
    my $output_msp = File::Spec->catfile($tmpdir, 'test_parse.msp');
    run_conversion($test_blib, $output_msp);
    
    open(my $fh, '<', $output_msp) or die "Cannot open $output_msp: $!";
    my @lines = <$fh>;
    close($fh);
    
    # Count entries (each entry starts with "Name:")
    my $entry_count = grep { /^Name:/i } @lines;
    is($entry_count, 4, 'MSP file contains 4 entries');
    
    # Verify each entry has required fields
    my $current_entry = {};
    my $entries_found = 0;
    my $in_peaks = 0;
    my $peak_count = 0;
    
    for my $line (@lines) {
        chomp $line;
        if ($line =~ /^Name:\s*(.+)/i) {
            # New entry
            if ($current_entry->{name}) {
                # Validate previous entry
                ok($current_entry->{name}, "Entry $entries_found has Name field");
                ok($current_entry->{mw}, "Entry $entries_found has MW field");
                ok($current_entry->{comment}, "Entry $entries_found has Comment field");
                ok($current_entry->{num_peaks} > 0, "Entry $entries_found has Num peaks field");
                is($current_entry->{peak_count}, $current_entry->{num_peaks}, 
                   "Entry $entries_found peak count matches");
            }
            $current_entry = { name => $1, peak_count => 0 };
            $entries_found++;
            $in_peaks = 0;
        } elsif ($line =~ /^MW:\s*([\d.]+)/i) {
            $current_entry->{mw} = $1;
        } elsif ($line =~ /^Comment:\s*(.+)/i) {
            $current_entry->{comment} = $1;
        } elsif ($line =~ /^Num\s*peaks:\s*(\d+)/i) {
            $current_entry->{num_peaks} = $1;
            $in_peaks = 1;
        } elsif ($in_peaks && $line =~ /^\s*([\d.]+)\s+([\d.]+)/) {
            $current_entry->{peak_count}++;
        } elsif ($line eq '') {
            $in_peaks = 0;
        }
    }
    
    # Validate last entry
    if ($current_entry->{name}) {
        ok($current_entry->{name}, "Entry $entries_found has Name field");
        ok($current_entry->{mw}, "Entry $entries_found has MW field");
        ok($current_entry->{comment}, "Entry $entries_found has Comment field");
        ok($current_entry->{num_peaks} > 0, "Entry $entries_found has Num peaks field");
        is($current_entry->{peak_count}, $current_entry->{num_peaks}, 
           "Entry $entries_found peak count matches");
    }
}

# Test 3: Verify spectrum 1 (IQVR/2, no mods)
{
    my $output_msp = File::Spec->catfile($tmpdir, 'test_spec1.msp');
    run_conversion($test_blib, $output_msp);
    
    open(my $fh, '<', $output_msp) or die "Cannot open $output_msp: $!";
    my @lines = <$fh>;
    close($fh);
    
    # Find first entry
    my $in_entry = 0;
    my %entry;
    my @peaks;
    
    for my $line (@lines) {
        chomp $line;
        if ($line =~ /^Name:\s*(.+)/i) {
            if ($in_entry) {
                last;  # Found next entry, stop
            }
            $entry{name} = $1;
            $in_entry = 1;
        } elsif ($in_entry) {
            if ($line =~ /^MW:\s*([\d.]+)/i) {
                $entry{mw} = $1;
            } elsif ($line =~ /^Comment:\s*(.+)/i) {
                $entry{comment} = $1;
            } elsif ($line =~ /^Num\s*peaks:\s*(\d+)/i) {
                $entry{num_peaks} = $1;
            } elsif ($line =~ /^\s*([\d.]+)\s+([\d.]+)/) {
                push @peaks, [$1, $2];
            } elsif ($line eq '' && @peaks > 0) {
                last;  # End of entry
            }
        }
    }
    
    like($entry{name}, qr/^IQVR\/2/, 'Spectrum 1 Name is IQVR/2');
    ok($entry{mw} > 0, 'Spectrum 1 has MW value');
    like($entry{comment}, qr/Mods=0/, 'Spectrum 1 has Mods=0');
    like($entry{comment}, qr/RetentionTime=120\.00/, 'Spectrum 1 RetentionTime preserved');
    like($entry{comment}, qr/Score=0\.95/, 'Spectrum 1 Score preserved');
    is(scalar(@peaks), 5, 'Spectrum 1 has 5 peaks');
    
    # Verify first peak
    if (@peaks) {
        ok(abs($peaks[0]->[0] - 175.119) < 0.01, 'Spectrum 1 first peak m/z correct');
        ok(abs($peaks[0]->[1] - 1000.0) < 0.01, 'Spectrum 1 first peak intensity correct');
    }
}

# Test 4: Verify spectrum 2 (MLQGR/2, Oxidation)
{
    my $output_msp = File::Spec->catfile($tmpdir, 'test_spec2.msp');
    run_conversion($test_blib, $output_msp);
    
    open(my $fh, '<', $output_msp) or die "Cannot open $output_msp: $!";
    my @lines = <$fh>;
    close($fh);
    
    # Find second entry
    my $entry_count = 0;
    my $in_entry = 0;
    my %entry;
    my @peaks;
    
    for my $line (@lines) {
        chomp $line;
        if ($line =~ /^Name:\s*(.+)/i) {
            $entry_count++;
            if ($entry_count == 2) {
                $entry{name} = $1;
                $in_entry = 1;
            } elsif ($entry_count > 2) {
                last;
            }
        } elsif ($in_entry) {
            if ($line =~ /^MW:\s*([\d.]+)/i) {
                $entry{mw} = $1;
            } elsif ($line =~ /^Comment:\s*(.+)/i) {
                $entry{comment} = $1;
            } elsif ($line =~ /^Num\s*peaks:\s*(\d+)/i) {
                $entry{num_peaks} = $1;
            } elsif ($line =~ /^\s*([\d.]+)\s+([\d.]+)/) {
                push @peaks, [$1, $2];
            } elsif ($line eq '' && @peaks > 0) {
                last;
            }
        }
    }
    
    like($entry{name}, qr/M.*LQGR\/2/, 'Spectrum 2 Name contains M...LQGR/2');
    like($entry{name}, qr/_1\(/, 'Spectrum 2 Name has modification count');
    like($entry{comment}, qr/Mods=1\(/, 'Spectrum 2 Comment has Mods=1');
    like($entry{comment}, qr/\(1,M,/, 'Spectrum 2 has modification at position 1 on M');
    is(scalar(@peaks), 6, 'Spectrum 2 has 6 peaks');
}

# Test 5: Verify spectrum 3 (LKCASLQK/3, Carbamidomethyl)
{
    my $output_msp = File::Spec->catfile($tmpdir, 'test_spec3.msp');
    run_conversion($test_blib, $output_msp);
    
    open(my $fh, '<', $output_msp) or die "Cannot open $output_msp: $!";
    my @lines = <$fh>;
    close($fh);
    
    # Find third entry
    my $entry_count = 0;
    my $in_entry = 0;
    my %entry;
    
    for my $line (@lines) {
        chomp $line;
        if ($line =~ /^Name:\s*(.+)/i) {
            $entry_count++;
            if ($entry_count == 3) {
                $entry{name} = $1;
                $in_entry = 1;
            } elsif ($entry_count > 3) {
                last;
            }
        } elsif ($in_entry && $line =~ /^Comment:\s*(.+)/i) {
            $entry{comment} = $1;
            last;
        }
    }
    
    like($entry{name}, qr/LKCASLQK\/3|LKC\[\+57\.0\]ASLQK\/3/, 'Spectrum 3 Name contains sequence/3');
    like($entry{comment}, qr/Mods=1\(/, 'Spectrum 3 Comment has Mods=1');
    like($entry{comment}, qr/\(3,C,Carbamidomethyl\)/, 'Spectrum 3 has Carbamidomethyl modification');
}

# Test 6: Verify spectrum 4 (SCRSYR/3, 2 mods)
{
    my $output_msp = File::Spec->catfile($tmpdir, 'test_spec4.msp');
    run_conversion($test_blib, $output_msp);
    
    open(my $fh, '<', $output_msp) or die "Cannot open $output_msp: $!";
    my @lines = <$fh>;
    close($fh);
    
    # Find fourth entry
    my $entry_count = 0;
    my $in_entry = 0;
    my %entry;
    
    for my $line (@lines) {
        chomp $line;
        if ($line =~ /^Name:\s*(.+)/i) {
            $entry_count++;
            if ($entry_count == 4) {
                $entry{name} = $1;
                $in_entry = 1;
            } elsif ($entry_count > 4) {
                last;
            }
        } elsif ($in_entry && $line =~ /^Comment:\s*(.+)/i) {
            $entry{comment} = $1;
            last;
        }
    }
    
    like($entry{name}, qr/SCRSYR\/3|S\[\+42\.0\]C\[\+57\.0\]RSYR\/3/, 'Spectrum 4 Name contains sequence/3');
    like($entry{name}, qr/_2\(/, 'Spectrum 4 Name has 2 modifications');
    like($entry{comment}, qr/Mods=2\(/, 'Spectrum 4 Comment has Mods=2');
    like($entry{comment}, qr/\(1,S,Acetyl\)/, 'Spectrum 4 has Acetyl modification');
    like($entry{comment}, qr/\(2,C,Carbamidomethyl\)/, 'Spectrum 4 has Carbamidomethyl modification');
}

# Test 7: Error handling - invalid BLIB file
{
    my $invalid_blib = File::Spec->catfile($tmpdir, 'invalid.blib');
    open(my $fh, '>', $invalid_blib) or die "Cannot create $invalid_blib: $!";
    print $fh "This is not a valid SQLite database\n";
    close($fh);
    
    my $output_msp = File::Spec->catfile($tmpdir, 'test_error.msp');
    my $result = run_conversion($invalid_blib, $output_msp);
    
    ok(!$result, 'Conversion fails for invalid BLIB file');
    ok(!-f $output_msp || -s $output_msp == 0, 'No output file created for invalid input');
}

done_testing();
