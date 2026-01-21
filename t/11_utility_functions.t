#!/usr/bin/perl
##############################################################################
# Unit tests for utility functions in blib2msp.pl
##############################################################################

use strict;
use warnings;
use Test::More;
use File::Spec;
use FindBin qw($RealBin);

# Find the main script
my $script_dir = File::Spec->catdir($RealBin, '..');
my $script = File::Spec->catfile($script_dir, 'blib2msp.pl');

unless (-f $script) {
    plan skip_all => "Main script not found: $script";
}

plan tests => 17;

# Load the main script as a module
{
    package main;
    our $VERSION;
    do $script or die "Cannot load script: $@";
}

# Test 1: get_timestamp function
ok(defined(&main::get_timestamp), 'get_timestamp function exists');

{
    my $ts = main::get_timestamp();
    like($ts, qr/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/, 'Timestamp format is YYYY-MM-DD HH:MM:SS');
}

# Test 2: format_duration function
ok(defined(&main::format_duration), 'format_duration function exists');

{
    # Test seconds
    my $result = main::format_duration(45);
    like($result, qr/45 seconds/, 'Format 45 seconds');
    
    # Test minutes and seconds
    $result = main::format_duration(125);
    like($result, qr/2 min 5 sec/, 'Format 2 min 5 sec');
    
    # Test hours, minutes, seconds
    $result = main::format_duration(3725);
    like($result, qr/1 hr 2 min 5 sec/, 'Format 1 hr 2 min 5 sec');
    
    # Test exact hour
    $result = main::format_duration(3600);
    like($result, qr/1 hr 0 min 0 sec/, 'Format exactly 1 hour');
}

# Test 3: track_modification function
ok(defined(&main::track_modification), 'track_modification function exists');

{
    # track_modification uses lexically scoped hashes, so we just verify it doesn't crash
    eval { main::track_modification(57.021464, 'C', 'Carbamidomethyl'); };
    is($@, '', 'track_modification handles known modification without error');
    
    eval { main::track_modification(123.456, 'M', undef); };
    is($@, '', 'track_modification handles unknown modification without error');
}

# Test 4: log_msg function (just verify it exists and doesn't crash)
ok(defined(&main::log_msg), 'log_msg function exists');

{
    # Temporarily capture STDERR
    my $stderr_output = '';
    {
        local *STDERR;
        open(STDERR, '>', \$stderr_output) or die "Cannot redirect STDERR: $!";
        
        # Log at different levels (LOG_INFO = 2)
        main::log_msg(2, 'Test info message');
    }
    
    like($stderr_output, qr/\[INFO\].*Test info message/, 'log_msg outputs formatted message');
}

# Test 5: print_modification_summary function (just verify it doesn't crash)
ok(defined(&main::print_modification_summary), 'print_modification_summary function exists');

{
    # Temporarily capture STDERR
    my $stderr_output = '';
    {
        local *STDERR;
        open(STDERR, '>', \$stderr_output) or die "Cannot redirect STDERR: $!";
        
        main::print_modification_summary();
    }
    
    like($stderr_output, qr/Modification Summary/, 'print_modification_summary outputs summary');
}

# Test 6: Test LOG constants
{
    is(&main::LOG_ERROR(), 0, 'LOG_ERROR is 0');
    is(&main::LOG_WARN(), 1, 'LOG_WARN is 1');
    is(&main::LOG_INFO(), 2, 'LOG_INFO is 2');
}

done_testing();
