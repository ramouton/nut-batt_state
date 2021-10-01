#!/usr/bin/perl

use strict;
use warnings;

my @valid_line_states = ('charging','discharging');
my @valid_batt_states = ('ok','warn','low','crit');

my @valid_upssched_signals = ('onbatt','online','replbatt','commbad','commok');




&main();
sub main() {
  my $incoming_upssched_signal = shift @ARGV;
  
  exit(0);
}